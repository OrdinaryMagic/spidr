require 'set'

module Spidr
  class Page
    # Reserved names used within Cookie strings
    RESERVED_COOKIE_NAMES = /^(?:Path|Expires|Domain|Secure|HTTPOnly)$/i

    #
    # The raw Cookie String sent along with the page.
    #
    # @return [String]
    #   The raw Cookie from the response.
    #
    # @since 0.2.7
    #
    def cookie
      @headers['Set-Cookie'] || ''
    end

    alias raw_cookie cookie

    #
    # The Cookie values sent along with the page.
    #
    # @return [Array<String>]
    #   The Cookies from the response.
    #
    # @since 0.2.2
    #
    def cookies
      # TODO: get_fields
      [@headers['Set-Cookie']].reject(&:blank?) || []
    end

    #
    # The Cookie key -> value pairs returned with the response.
    #
    # @return [Hash{String => String}]
    #   The cookie keys and values.
    #
    # @since 0.2.2
    #
    def cookie_params
      params = {}

      cookies.each do |value|
        value.split(';').each do |param|
          param.strip!

          name, value = param.split('=', 2)

          params[name] = (value || '') unless name =~ RESERVED_COOKIE_NAMES
        end
      end

      params
    end
  end
end
