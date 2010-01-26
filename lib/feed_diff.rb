require 'nokogiri'

class FeedDiff

  class FeedContentHandler < Nokogiri::XML::SAX::Document
    """Sax content handler for quickly parsing Atom and RSS feeds."""

    def initialize
      """Initializer.

      Args:
        parser: Instance of the xml.sax parser being used with this handler.
      """
      @header_footer = ""
      @entries_map = {}

      # Internal state
      @stack_level = 0
      @output_stack = []
      @current_level = []
      @last_id = ''
      @last_link = ''
      @last_title = ''
      @last_description = ''
    end

    def header_footer
      @header_footer
    end

    def entries_map
      @entries_map
    end

    # Helper methods
    def emit(data)
      if data.class == Array
        @current_level.concat(data)
      else
        @current_level << data
      end
    end

    def push
      @current_level = []
      @output_stack << @current_level
    end

    def pop
      old_level = @output_stack.pop
      if @output_stack.size > 0
        @current_level = @output_stack[-1]
      else
        @current_level = nil
      end
      return old_level
    end

    # SAX methods
    def start_element(name, attrs)
      @stack_level += 1
      event = [@stack_level, name]
      logger.debug("Start stack level #{event.inspect}")
      push
      emit(['<', name])
      attrs = make_hash(attrs)
      attrs.each_pair do |key, value|
        emit([' ', key, '=', quoteattr(value)])
        # Do not emit a '>' here because this tag may need to be immediately
        # closed with a '/> ending.
      end
      push
    end

    def end_element(name)
      event = [@stack_level, name]
      #logger.debug ("End stack level #{event.inspect}")

      content = pop
      if content
        emit('>')
        emit(content)
        emit(['</', name, '>'])
      else
        # No content means this element should be immediately closed.
        emit('/>')
      end

      handle_event(event, content)
      @stack_level -= 1
    end

    def characters(content)
      # The SAX parser will try to escape XML entities (like &amp;) and other
      # fun stuff. But this is not what we actually want. We want the original
      # content to be reproduced exactly as we received it, so we can pass it
      # along to others. The reason is simple: reformatting the XML by unescaping
      # certain data may cause the resulting XML to no longer validate.
      emit(content.escape_xml)
    end

    def strip_whitespace(enclosing_tag, all_parts)
      """Strips the whitespace from a SAX parser list for a feed.

    Args:
      enclosing_tag: The enclosing tag of the feed.
      all_parts: List of SAX parser elements.

    Returns:
      header_footer for those parts with trailing whitespace removed.
    """

      if enclosing_tag.include? 'feed'

        all_parts.to_array! unless all_parts.class == Array

        first_part = all_parts[0..-4].join('')
        first_part = first_part.gsub(/[\n\r\t]/, '')
        return "#{first_part}</#{enclosing_tag}>"

      else
        all_parts.to_array! unless all_parts.class == Array

        first_part = all_parts[0..-4].join('')
        first_part = first_part.gsub(/[\n\r\t] +/, '')
        channel_part = first_part.rindex('</channel>')

        if channel_part.nil?
          raise 'Could not find </channel> after trimming whitespace'
        end

        stripped = first_part[0..channel_part-1].gsub(/[\n\r\t]/, '')
        return "#{stripped}</channel></#{enclosing_tag}>"
      end

    end

    # todo - check the below, added

    def make_hash(attrs)
      hashes = {}
      skip_next = false
      attrs.each_with_index do |attr, index|
        if skip_next
          skip_next = false
          next
        end
        if attr.class == Array and attr.size == 2
          hashes[attr[0]] = attr[1]
        else
          unless index == attrs.size-1
            hashes[attr] = attrs[index + 1]
            skip_next = true
          end
        end
      end
      hashes
    end

    def quoteattr(data, entities={})
      """Escape and quote an attribute value.

      Escape &, <, and > in a string of data, then quote it for use as
      an attribute value.  The \" character will be escaped as well, if
      necessary.

      You can escape other strings of data by passing a dictionary as
      the optional entities parameter.  The keys and values must all be
      strings; each key will be replaced with its corresponding value.
      """

      #entities.update({'\n': '&#10;', '\r': '&#13;', '\t':'&#9;'})

      if data.include? '"'
        if data.include? "'"
          data = '"' + data.gsub('"', "&quot;") + '"'
        else
          data = '"' + data + '"'
        end

      else
        data = data = '"' + data + '"'
      end
      data
    end

  end

  class AtomFeedHandler < FeedContentHandler
    """Sax content handler for Atom feeds."""

    def handle_event(event, content)
      depth, tag = event[0], event[1].downcase

      if event[0] == 1
        if !tag.eql? 'feed':
          raise 'Enclosing tag is not <feed></feed>'
        else
          @header_footer = strip_whitespace(event[1], pop)
        end
      elsif event == [2, 'entry']
        @entries_map[@last_id] = pop.join('')
      elsif event == [3, 'id']:
        @last_id = content.join('').strip()
        emit(pop)
      else
        emit(pop)
      end
    end

  end

  class RssFeedHandler < FeedContentHandler
    """Sax content handler for RSS feeds."""

    def handle_event(event, content)
      depth, tag = event[0], event[1].downcase
      if event[0] == 1
        if tag.downcase != 'rss' and !(tag.include? 'rdf')
          raise 'Enclosing tag is not <rss></rss> or <rdf></rdf>'
        else
          @header_footer = strip_whitespace(event[1], pop)
        end
      elsif event == [3, 'item']
        item_id = nil
        item_id = @last_id if !(@last_id.blank?) and item_id.nil?
        item_id = @last_link if !(@last_link.blank?) and item_id.nil?
        item_id = @last_title if !(@last_title.blank?) and item_id.nil?
        item_id = @last_description if !(@last_description.blank?) and item_id.nil?

        @entries_map[item_id] = pop.join('')
        @last_id, @last_link, @last_title, @last_description = ['', '', '', '']
      elsif event == [4, 'guid']
        @last_id = content.join('').strip()
        emit(pop())
      elsif event == [4, 'link']
        @last_link = content.join('').strip()
        emit(pop())
      elsif event == [4, 'title']
        @last_title = content.join('').strip()
        emit(pop())
      elsif event == [4, 'description']
        @last_description = content.join('').strip()
        emit(pop())
      else
        emit(pop())
      end

    end
  end

  def filter(data, format)
    """Filter a feed through the parser.

    Args:
      data: String containing the data of the XML feed to parse.
      format: String naming the format of the data. Should be 'rss' or 'atom'.

    Returns:
      Tuple (header_footer, entries_map) where:
        header_footer: String containing everything else in the feed document
          that is specifically *not* an <entry> or <item>.
        entries_map: Dictionary mapping entry_id to the entry's XML data.

    Raises:
      xml.sax.SAXException on parse errors. feed_diff.Error if the diff could not
      be derived due to bad content (e.g., a good XML doc that is not Atom or RSS)
      or any of the feed entries are missing required fields.
    """
    if format.eql? 'atom'
      handler = AtomFeedHandler.new
    elsif format.eql? 'rss'
      handler = RssFeedHandler.new
    else
      raise "Invalid feed format \"#{format}\""
    end

    parser = Nokogiri::XML::SAX::Parser.new(handler)

    begin
      parser.parse(data)
    rescue IOError => e
      raise "Encountered IOError while parsing: #{e.message}"
    end

    handler.entries_map.each do |entry_id, content|

      if format.eql? 'atom' and entry_id.blank?
        raise "<entry> element missing <id>: #{content}"
      elsif format.eql? 'rss' and entry_id.blank?
        raise "<item> element missing <guid> or <link>: #{content}"
      end

    end

    return handler.header_footer, handler.entries_map

  end

end