module Sinatra
  class Request
    def get(parameter, default = '')
      if params
        return default if params[parameter].nil?
        params[parameter]
      else
        default
      end
    end

    def get_all(parameter, default = '')
      return [default] if parameter.nil?
      [get(parameter, default)]
    end
  end
end

module Sinatra
  class Base
    def is_valid_url(url)
      begin
        uri = URI.parse(url)
        if uri.class != URI::HTTP
          return false
        end
        if uri.to_s.include? "#"
          return false
        end
      rescue URI::InvalidURIError
        return false
      end
      true
    end

    def normalize_iri(url)
      # todo...
      url
    end

    def utf8encoded(string)
      """Encodes a string as utf-8 data and returns an ascii string.

      Args:
        data: The string data to encode.

      Returns:
        An ascii string, or None if the 'data' parameter was None.
      """
      if string.nil?
        return nil
      end

#      todo...
#      if isinstance(data, unicode)
#        return unicode(data).encode('utf-8')
#        string.split(//u).reverse.join
#      else
#        return data
#      end

      string
    end

    VALID_CHARS = [
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
            'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
            'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '_',
    ]

    def get_random_challenge()
      """Returns a string containing a random challenge token."""
      o = VALID_CHARS.map{|i| i.to_a}.flatten;
      (0..128).map{ o[rand(o.length)] }.join;
    end

    def requestify(value, prefix = nil)
      case value
        when Array
          value.map do |v|
            requestify(v, "#{prefix}[]")
          end.join("&")
        when Hash
          value.map do |k, v|
            requestify(v, prefix ? "#{prefix}[#{escape(k)}]" : escape(k))
          end.join("&")
        else
          "#{prefix}=#{escape(value)}"
      end
    end

  end

end
