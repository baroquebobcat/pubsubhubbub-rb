require 'nokogiri'

class FeedIdentifierDocument < Nokogiri::XML::SAX::Document

  def initialize
    @link = nil
    @tag_stack = []
    @target_tag_stack = nil
    @capture_next_element = false
  end

  def start_element name, attrs = []

    unless @link
      @tag_stack << name

      if @tag_stack.size == @target_tag_stack.size
        equal = true

        @target_tag_stack.each_with_index do |target_tag, index|

          unless @tag_stack[index] =~ /#{target_tag}/
            equal = false
            break
          end
        end

        if equal
          @capture_next_element = true
        end
      end
    end
  end

  def characters(content)
    if @capture_next_element
      @link = content
    end
  end

  def end_element(name)
    if @link
      @capture_next_element = false
    else
      @tag_stack.pop
    end
  end

  def get_link
    unless @link
      return nil
    else
      return @link
    end
  end

end

class AtomFeedIdentifierDocument < FeedIdentifierDocument
  def initialize
    super
    @target_tag_stack = ['feed', 'id']
  end
end

class RssFeedIdentifierDocument < FeedIdentifierDocument
  def initialize
    super
    @target_tag_stack = ['(.*rss.*)|(.*rdf.*)', 'channel', 'link']
  end
end

class FeedIdentifier

  def identify(data, format)
    """Identifies a feed.

    Args:
      data: String containing the data of the XML feed to parse.
      format: String naming the format of the data. Should be 'rss' or 'atom'.

    Returns:
      The ID of the feed, or None if one could not be determined (due to parse
      errors, etc).

    Raises:
      xml.sax.SAXException on parse errors.
    """

    if format.eql? 'atom'
      handler = AtomFeedIdentifierDocument.new
    elsif format.eql? 'rss'
      handler = RssFeedIdentifierDocument.new
    else
      raise "Invalid feed format \"#{format}\""
    end

    parser = Nokogiri::XML::SAX::Parser.new(handler)
    parser.parse(data)

    return handler.get_link()

  end

end
