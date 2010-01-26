class String

  @@xml_char_to_escape = {
          '&' => '&amp;',
          '<' => '&lt;',
          '>' => '&gt;',
          "'" => '&apos;',
          '"' => '&quot;'
  }
  @@xml_unescape_to_char = {
          '&amp;' => '&',
          '&lt;' => '<',
          '&gt;' => '>',
          '&apos;' => "'",
          '&quot;' => '"'
  }

  def escape_xml
    return gsub(/[&<>'"]/) do | match |
      @@xml_char_to_escape[match]
    end
  end

  def unescape_xml
    result = self.dup
    @@xml_unescape_to_char.each_pair do |escape_sequence, char|
      result = result.gsub(escape_sequence, char)
    end
    return result
  end

end
