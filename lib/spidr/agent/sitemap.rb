require 'set'

module Spidr
  class Agent
    # Common locations for Sitemap(s)
    COMMON_SITEMAP_LOCATIONS = %w[
      sitemap.xml
      sitemap.xml.gz
      sitemap.gz
      sitemap_index.xml
      sitemap-index.xml
      sitemap_index.xml.gz
      sitemap-index.xml.gz
    ].freeze

    #
    # Initializes the sitemap fetcher.
    #
    def initialize_sitemap(options)
      @sitemap = options.fetch(:sitemap, false)
    end

    #
    # Returns the URLs found as per the sitemap.xml spec.
    #
    # @return [Array<URI::HTTP>, Array<URI::HTTPS>]
    #   The URLs found.
    #
    # @see https://www.sitemaps.org/protocol.html
    def sitemap_urls(url)
      return [] unless @sitemap

      base_url = to_base_url(url)

      return parse_sitemap(url: URI.join(base_url, @sitemap).to_s) if @sitemap.is_a?(String)

      if @sitemap == :robots
        urls = robots.other_values(base_url).transform_keys(&:downcase)['sitemap']
        return urls.flat_map { |u| parse_sitemap(url: u) } if urls && urls.any?
      end

      COMMON_SITEMAP_LOCATIONS.each do |path|
        page = get_page(URI.join(base_url, path).to_s, true)
        return parse_sitemap(page: page) if page.code == 200
      end

      []
    end

    private

    def robots
      return @robots if @robots
      return unless @sitemap == :robots

      raise(ArgumentError, ":robots option given but unable to require 'robots' gem") unless Object.const_defined?(:Robots)

      Robots.new(@user_agent)
    end

    def parse_sitemap(url: nil, page: nil)
      page = get_page(url, true) if page.nil?
      return [] unless page

      if page.sitemap_index?
        page.each_sitemap_index_url.flat_map { |u| parse_sitemap(url: u) }
      else
        page.sitemap_urls
      end
    end

    def to_base_url(url)
      uri = url
      uri = URI.parse(url) unless url.is_a?(URI)

      "#{uri.scheme}://#{uri.host}"
    end
  end
end
