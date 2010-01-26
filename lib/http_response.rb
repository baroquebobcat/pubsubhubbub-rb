module Net
  class HTTPResponse
    def headers
      headers = {}
      @header.each do |k,va|
         headers[k] = va.join(', ')
      end
      headers
    end
  end
end

