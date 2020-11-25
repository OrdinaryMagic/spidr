require 'uri'

module Spidr
  class Agent

    # Specifies whether the Agent will strip URI fragments
    attr_accessor :strip_fragments

    # Specifies whether the Agent will strip URI queries
    attr_accessor :strip_query

    #
    # Sanitizes a URL based on filtering options.
    #
    # @param [URI::HTTP, URI::HTTPS, String] url
    #   The URL to be sanitized
    #
    # @return [URI::HTTP, URI::HTTPS]
    #   The new sanitized URL.
    #
    # @since 0.2.2
    #
    def sanitize_url(url)
      url = URI(url.chomp('/'))

      url.fragment = nil if @strip_fragments
      url.query    = nil if @strip_query

      url
    end

    protected

    #
    # Initializes the Sanitizer rules.
    #
    # @param [Hash] options
    #   Additional options.
    #
    # @option options [Boolean] :strip_fragments (true)
    #   Specifies whether or not to strip the fragment component from URLs.
    #
    # @option options [Boolean] :strip_query (false)
    #   Specifies whether or not to strip the query component from URLs.
    #
    # @since 0.2.2
    #
    def initialize_sanitizers(options={})
      @strip_fragments = options.fetch(:strip_fragments,true)
      @strip_query     = options.fetch(:strip_query,false)
    end

  end
end
