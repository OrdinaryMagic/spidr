require 'spidr/settings/user_agent'
require 'spidr/agent/sanitizers'
require 'spidr/agent/filters'
require 'spidr/agent/events'
require 'spidr/agent/actions'
require 'spidr/agent/robots'
require 'spidr/agent/sitemap'
require 'spidr/page'
require 'spidr/session_cache'
require 'spidr/cookie_jar'
require 'spidr/auth_store'
require 'spidr/spidr'

require 'openssl'
require 'net/http'
require 'set'
require 'concurrent'
require 'curb'

module Spidr
  class Agent

    include Settings::UserAgent

    # HTTP Host Header to use
    #
    # @return [String]
    attr_accessor :host_header

    # HTTP Host Headers to use for specific hosts
    #
    # @return [Hash{String,Regexp => String}]
    attr_reader :host_headers

    # HTTP Headers to use for every request
    #
    # @return [Hash{String => String}]
    #
    # @since 0.6.0
    attr_reader :default_headers

    # HTTP Authentication credentials
    #
    # @return [AuthStore]
    attr_accessor :authorized

    # Referer to use
    #
    # @return [String]
    attr_accessor :referer

    # Delay in between fetching pages
    #
    # @return [Integer]
    attr_accessor :delay

    # History containing visited URLs
    #
    # @return [Set<URI::HTTP>]
    attr_reader :history

    # List of unreachable URLs
    #
    # @return [Set<URI::HTTP>]
    attr_reader :failures

    # Queue of URLs to visit
    #
    # @return [Array<URI::HTTP>]
    attr_reader :queue

    # Queue of skipped URLs
    #
    # @return [Array<URI::HTTP>]
    attr_reader :skipped_queue

    # The session cache
    #
    # @return [SessionCache]
    #
    # @since 0.6.0
    attr_reader :sessions

    # Cached cookies
    #
    # @return [CookieJar]
    attr_reader :cookies

    # Maximum number of pages to visit.
    #
    # @return [Integer]
    attr_reader :limit

    # Maximum depth
    #
    # @return [Integer]
    attr_reader :max_depth

    # The visited URLs and their depth within a site
    #
    # @return [Hash{URI::HTTP => Integer}]
    attr_reader :levels

    attr_reader :pool_size

    #
    # Creates a new Agent object.
    #
    # @param [Hash] options
    #   Additional options
    #
    # @option options [Integer] :open_timeout (Spidr.open_timeout)
    #   Optional open timeout.
    #
    # @option options [Integer] :read_timeout (Spidr.read_timeout)
    #   Optional read timeout.
    #
    # @option options [Integer] :ssl_timeout (Spidr.ssl_timeout)
    #   Optional ssl timeout.
    #
    # @option options [Integer] :continue_timeout (Spidr.continue_timeout)
    #   Optional continue timeout.
    #
    # @option options [Integer] :keep_alive_timeout (Spidr.keep_alive_timeout)
    #   Optional keep_alive timeout.
    #
    # @option options [Hash] :proxy (Spidr.proxy)
    #   The proxy information to use.
    #
    # @option :proxy [String] :host
    #   The host the proxy is running on.
    #
    # @option :proxy [Integer] :port
    #   The port the proxy is running on.
    #
    # @option :proxy [String] :user
    #   The user to authenticate as with the proxy.
    #
    # @option :proxy [String] :password
    #   The password to authenticate with.
    #
    # @option options [Hash{String => String}] :default_headers
    #   Default headers to set for every request.
    #
    # @option options [String] :host_header
    #   The HTTP Host header to use with each request.
    #
    # @option options [Hash{String,Regexp => String}] :host_headers
    #   The HTTP Host headers to use for specific hosts.
    #
    # @option options [String] :user_agent (Spidr.user_agent)
    #   The User-Agent string to send with each requests.
    #
    # @option options [String] :referer
    #   The Referer URL to send with each request.
    #
    # @option options [Integer] :delay (0)
    #   The number of seconds to pause between each request.
    #
    # @option options [Set, Array] :queue
    #   The initial queue of URLs to visit.
    #
    # @option options [Set, Array] :history
    #   The initial list of visited URLs.
    #
    # @option options [Integer] :limit
    #   The maximum number of pages to visit.
    #
    # @option options [Integer] :max_depth
    #   The maximum link depth to follow.
    #
    # @option options [Boolean] :robots (Spidr.robots?)
    #   Specifies whether `robots.txt` should be honored.
    #
    # @yield [agent]
    #   If a block is given, it will be passed the newly created agent
    #   for further configuration.
    #
    # @yieldparam [Agent] agent
    #   The newly created agent.
    #
    # @see #initialize_sanitizers
    # @see #initialize_filters
    # @see #initialize_actions
    # @see #initialize_events
    #
    def initialize(options = {})
      @host_header  = options[:host_header]
      @host_headers = {}

      @host_headers.merge!(options[:host_headers]) if options[:host_headers]

      @default_headers = {}

      @default_headers.merge!(options[:default_headers]) if options[:default_headers]

      @user_agent = options.fetch(:user_agent,Spidr.user_agent)
      @referer    = options[:referer]

      @sessions   = SessionCache.new(options)
      @cookies    = CookieJar.new
      @authorized = AuthStore.new

      @running  = false
      @delay    = options.fetch(:delay, 0)
      @history  = Set[]
      @failures = Set[]
      @queue    = []
      @skipped_queue = Set[]

      @limit     = options[:limit]
      @levels    = Hash.new(0)
      @max_depth = options[:max_depth]
      @mutex = Mutex.new
      @pool_size = options.fetch(:pool_size, 8)

      self.queue = options[:queue] if options[:queue]
      self.history = options[:history] if options[:history]
      self.skipped_queue = options[:skipped_queue] if options[:skipped_queue]

      initialize_sanitizers(options)
      initialize_filters(options)
      initialize_actions(options)
      initialize_events(options)

      initialize_robots if options.fetch(:robots, Spidr.robots?)
      initialize_sitemap(options)

      yield self if block_given?
    end

    #
    # Creates a new agent and begin spidering at the given URL.
    #
    # @param [URI::HTTP, String] url
    #   The URL to start spidering at.
    #
    # @param [Hash] options
    #   Additional options. See {Agent#initialize}.
    #
    # @yield [agent]
    #   If a block is given, it will be passed the newly created agent
    #   before it begins spidering.
    #
    # @yieldparam [Agent] agent
    #   The newly created agent.
    #
    # @see #initialize
    # @see #start_at
    #
    def self.start_at(url, options = {}, &block)
      agent = new(options, &block)
      agent.start_at(url)
    end

    #
    # Creates a new agent and spiders the web-site located at the given URL.
    #
    # @param [URI::HTTP, String] url
    #   The web-site to spider.
    #
    # @param [Hash] options
    #   Additional options. See {Agent#initialize}.
    #
    # @yield [agent]
    #   If a block is given, it will be passed the newly created agent
    #   before it begins spidering.
    #
    # @yieldparam [Agent] agent
    #   The newly created agent.
    #
    # @see #initialize
    #
    def self.site(url,options={},&block)
      url = URI(url)

      agent = new(options.merge(host: url.host),&block)
      agent.start_at(url)
    end

    #
    # Creates a new agent and spiders the given host.
    #
    # @param [String] name
    #   The host-name to spider.
    #
    # @param [Hash] options
    #   Additional options. See {Agent#initialize}.
    #
    # @yield [agent]
    #   If a block is given, it will be passed the newly created agent
    #   before it begins spidering.
    #
    # @yieldparam [Agent] agent
    #   The newly created agent.
    #
    # @see #initialize
    #
    def self.host(name,options={},&block)
      agent = new(options.merge(host: name),&block)
      agent.start_at(URI::HTTP.build(host: name, path: '/'))
    end

    #
    # The proxy information the agent uses.
    #
    # @return [Proxy]
    #   The proxy information.
    #
    # @see SessionCache#proxy
    #
    # @since 0.2.2
    #
    def proxy
      @sessions.proxy
    end

    #
    # Sets the proxy information that the agent uses.
    #
    # @param [Proxy] new_proxy
    #   The new proxy information.
    #
    # @return [Hash]
    #   The new proxy information.
    #
    # @see SessionCache#proxy=
    #
    # @since 0.2.2
    #
    def proxy=(new_proxy)
      @sessions.proxy = new_proxy
    end

    #
    # Clears the history of the agent.
    #
    def clear
      @queue.clear
      @history.clear
      @skipped_queue.clear
      @failures.clear
      return self
    end

    #
    # Start spidering at a given URL.
    #
    # @param [URI::HTTP, String] url
    #   The URL to start spidering at.
    #
    # @yield [page]
    #   If a block is given, it will be passed every page visited.
    #
    # @yieldparam [Page] page
    #   A page which has been visited.
    #
    def start_at(url, &block)
      urls = sitemap_urls(url)
      enqueue(urls)
      enqueue(url)
      run(&block)
    end

    #
    # Start spidering until the queue becomes empty or the agent is
    # paused.
    #
    # @yield [page]
    #   If a block is given, it will be passed every page visited.
    #
    # @yieldparam [Page] page
    #   A page which has been visited.
    #
    def run(&block)
      @running = true

      until @queue.empty? || paused? || limit_reached?
        limited_queue = @queue.shift(limit_balance || @queue.length)
        queue_processing(limited_queue, &block)
      end

      @running = false
      @sessions.clear
      self
    end

    def queue_processing(limited_queue, &block)
      pages = []
      pool = ::Concurrent::FixedThreadPool.new(@pool_size)
      limited_queue.each do |url|
        pool.post do
          page = get_page(url)
          @mutex.synchronize { pages << page }
        end
      end
      pool.shutdown
      pool.wait_for_termination
      finded_urls = Set[]
      pages.each do |p|
        urls = visit_page(p, &block)
        urls.each { |u| finded_urls << u } if urls.present?
      end
      enqueue(finded_urls.to_a)
    end

    #
    # Determines if the agent is running.
    #
    # @return [Boolean]
    #   Specifies whether the agent is running or stopped.
    #
    def running?
      @running == true
    end

    #
    # Sets the history of URLs that were previously visited.
    #
    # @param [#each] new_history
    #   A list of URLs to populate the history with.
    #
    # @return [Set<URI::HTTP>]
    #   The history of the agent.
    #
    # @example
    #   agent.history = ['http://tenderlovemaking.com/2009/05/06/ann-nokogiri-130rc1-has-been-released/']
    #
    def history=(new_history)
      @history.clear

      new_history.each do |url|
        @history << URI(url)
      end

      @history
    end

    alias visited_urls history

    #
    # Specifies the links which have been visited.
    #
    # @return [Array<String>]
    #   The links which have been visited.
    #
    def visited_links
      @history.map(&:to_s)
    end

    #
    # Specifies all hosts that were visited.
    #
    # @return [Array<String>]
    #   The hosts which have been visited.
    #
    def visited_hosts
      visited_urls.map(&:host).uniq
    end

    #
    # Determines whether a URL was visited or not.
    #
    # @param [URI::HTTP, String] url
    #   The URL to search for.
    #
    # @return [Boolean]
    #   Specifies whether a URL was visited.
    #
    def visited?(url)
      @history.include?(URI(url))
    end

    #
    # Sets the list of failed URLs.
    #
    # @param [#each] new_failures
    #   The new list of failed URLs.
    #
    # @return [Array<URI::HTTP>]
    #   The list of failed URLs.
    #
    # @example
    #   agent.failures = ['http://localhost/']
    #
    def failures=(new_failures)
      @failures.clear

      new_failures.each do |url|
        @failures << URI(url)
      end

      @failures
    end

    #
    # Determines whether a given URL could not be visited.
    #
    # @param [URI::HTTP, String] url
    #   The URL to check for failures.
    #
    # @return [Boolean]
    #   Specifies whether the given URL was unable to be visited.
    #
    def failed?(url)
      @failures.include?(URI(url))
    end

    alias pending_urls queue

    #
    # Sets the queue of URLs to visit.
    #
    # @param [#each] new_queue
    #   The new list of URLs to visit.
    #
    # @return [Array<URI::HTTP>]
    #   The list of URLs to visit.
    #
    # @example
    #   agent.queue = ['http://www.vimeo.com/', 'http://www.reddit.com/']
    #
    def queue=(new_queue)
      @queue.clear
      new_queue.each { |url| enqueue(url) }
      @queue
    end

    #
    # Sets the queue of skipped URLs.
    #
    # @param [#each] new_queue
    #   The new list of skipped URLs.
    #
    # @return [Array<URI::HTTP>]
    #   The list of skipped URLs.
    #
    # @example
    #   agent.skipped_queue = ['http://www.vimeo.com/', 'http://www.reddit.com/']
    #
    def skipped_queue=(new_queue)
      @skipped_queue.clear
      new_queue.each { |url| @skipped_queue << URI(url) }
      @skipped_queue
    end

    #
    # Enqueues a given URL to skipped queue.
    #
    # @param [URI::HTTP, String] url
    #   The URL to enqueue for visiting.
    #
    # @return [Boolean]
    #   Specifies whether the URL was enqueued, or ignored.
    #
    def enqueue_skipped(url)
      @skipped_queue << URI(url)
    end

    #
    # Determines whether a given URL has skipped.
    #
    # @param [URI::HTTP] url
    #   The URL to search for in the queue.
    #
    # @return [Boolean]
    #   Specifies whether the given URL has been skipped.
    #
    def skipped?(url)
      @skipped_queue.include?(url)
    end

    #
    # Determines whether a given URL has been enqueued.
    #
    # @param [URI::HTTP] url
    #   The URL to search for in the queue.
    #
    # @return [Boolean]
    #   Specifies whether the given URL has been queued for visiting.
    #
    def queued?(url)
      @queue.include?(url)
    end

    #
    # Enqueues a given URL for visiting, only if it passes all of the
    # agent's rules for visiting a given URL.
    #
    # @param [URI::HTTP, String] url
    #   The URL to enqueue for visiting.
    #
    # @return [Boolean]
    #   Specifies whether the URL was enqueued, or ignored.
    #
    def enqueue(item, level = 0)
      if item.is_a?(Array)
        return false if item.blank?

        item = item.map { |u| sanitize_url(u) }.filter { |u| valid?(u) }
        @queue |= (item - @history.to_a)
        return true
      end

      url = sanitize_url(item)
      if !queued?(url) && visit?(url)
        link = url.to_s

        begin
          @every_url_blocks.each { |url_block| url_block.call(url) }

          @every_url_like_blocks.each do |pattern,url_blocks|
            match = case pattern
                    when Regexp
                      link =~ pattern
                    else
                      (pattern == link) || (pattern == url)
                    end

            url_blocks.each { |url_block| url_block.call(url) } if match
          end
        rescue Actions::Paused => action
          raise(action)
        rescue Actions::SkipLink
          return false
        rescue Actions::Action
        end

        @queue << url
        @levels[url] = level
        return true
      end
      false
    end

    #
    # Requests and creates a new Page object from a given URL.
    #
    # @param [URI::HTTP] url
    #   The URL to request.
    #
    # @yield [page]
    #   If a block is given, it will be passed the page that represents the
    #   response.
    #
    # @yieldparam [Page] page
    #   The page for the response.
    #
    # @return [Page, nil]
    #   The page for the response, or `nil` if the request failed.
    #
    def get_page(url, sitemap = false)
      # url = URI(url)
      curl = init_curl(url.to_s, sitemap)
      curl.perform
      url = URI.parse(curl.last_effective_url) if sitemap
      new_page = Page.new(url, curl, sitemap)
      yield new_page if block_given?
      new_page
      # prepare_request(url) do |session, path, headers|
      #   response = follow_redirect ? process_url(session, path, headers, limit = 10) : session.get(path, headers)
      #   new_page = Page.new(url, response)
      #
      #   # save any new cookies
      #   @cookies.from_page(new_page)
      #
      #   yield new_page if block_given?
      #   return new_page
      # end
    end
    #
    # def process_url(session, path, headers, limit = 10)
    #   raise ArgumentError, 'too many HTTP redirects' if limit.zero?
    #
    #   response = session.get(path, headers)
    #   case response
    #   when Net::HTTPSuccess then
    #     response
    #   when Net::HTTPRedirection then
    #     process_url(session, response['location'], headers, limit - 1)
    #   else
    #     response
    #   end
    # end
    #
    def init_curl(url, sitemap = false)
      Curl::Easy.new do |c|
        c.url = url
        c.version = Curl::HTTP_1_1
        c.follow_location = sitemap
        c.timeout = 30 if sitemap
        # c.proxy_url = proxy_url if proxy_url.present?
        c.headers['User-Agent'] = @user_agent if @user_agent
      end
    end

    #
    # Posts supplied form data and creates a new Page object from a given URL.
    #
    # @param [URI::HTTP] url
    #   The URL to request.
    #
    # @param [String] post_data
    #   Form option data.
    #
    # @yield [page]
    #   If a block is given, it will be passed the page that represents the
    #   response.
    #
    # @yieldparam [Page] page
    #   The page for the response.
    #
    # @return [Page, nil]
    #   The page for the response, or `nil` if the request failed.
    #
    # @since 0.2.2
    #
    def post_page(url, post_data = '')
      url = URI(url)

      prepare_request(url) do |session,path,headers|
        new_page = Page.new(url,session.post(path,post_data,headers))

        # save any new cookies
        @cookies.from_page(new_page)

        yield new_page if block_given?
        return new_page
      end
    end

    #
    # Visits a given URL, and enqueus the links recovered from the URL
    # to be visited later.
    #
    # @param [URI::HTTP, String] url
    #   The URL to visit.
    #
    # @yield [page]
    #   If a block is given, it will be passed the page which was visited.
    #
    # @yieldparam [Page] page
    #   The page which was visited.
    #
    # @return [Page, nil]
    #   The page that was visited. If `nil` is returned, either the request
    #   for the page failed, or the page was skipped.
    #
    def visit_page(page)
      @history << page.url
      begin
        @every_page_blocks.each { |page_block| page_block.call(page) }
        yield page if block_given?
      rescue Actions::Paused => action
        raise(action)
      rescue Actions::SkipPage
        enqueue_skipped(page.url)
        return nil
      rescue Actions::Action
      end

      page.urls
    end

    #
    # Converts the agent into a Hash.
    #
    # @return [Hash]
    #   The agent represented as a Hash containing the `history` and
    #   the `queue` of the agent.
    #
    def to_hash
      { history: @history, queue: @queue, skipped_queue: @skipped_queue }
    end

    protected

    #
    # Prepares request headers for the given URL.
    #
    # @param [URI::HTTP] url
    #   The URL to prepare the request headers for.
    #
    # @return [Hash{String => String}]
    #   The prepared headers.
    #
    # @since 0.6.0
    #
    def prepare_request_headers(url)
      # set any additional HTTP headers
      headers = @default_headers.dup

      unless @host_headers.empty?
        @host_headers.each do |name,header|
          if url.host.match(name)
            headers['Host'] = header
            break
          end
        end
      end

      headers['Host']     ||= @host_header if @host_header
      headers['User-Agent'] = @user_agent if @user_agent
      headers['Referer']    = @referer if @referer

      if (authorization = @authorized.for_url(url))
        headers['Authorization'] = "Basic #{authorization}"
      end

      if (header_cookies = @cookies.for_host(url.host))
        headers['Cookie'] = header_cookies
      end

      return headers
    end

    #
    # Normalizes the request path and grabs a session to handle page
    # get and post requests.
    #
    # @param [URI::HTTP] url
    #   The URL to request.
    #
    # @yield [request]
    #   A block whose purpose is to make a page request.
    #
    # @yieldparam [Net::HTTP] session
    #   An HTTP session object.
    #
    # @yieldparam [String] path
    #   Normalized URL string.
    #
    # @yieldparam [Hash] headers
    #   A Hash of request header options.
    #
    # @since 0.2.2
    #
    def prepare_request(url,&block)
      path = unless url.path.empty?
               url.path
             else
               '/'
             end

      # append the URL query to the path
      path += "?#{url.query}" if url.query

      headers = prepare_request_headers(url)

      begin
        sleep(@delay) if @delay > 0

        yield @sessions[url], path, headers
      rescue SystemCallError,
             Timeout::Error,
             SocketError,
             IOError,
             OpenSSL::SSL::SSLError,
             Net::HTTPBadResponse,
             Zlib::Error => error

        @sessions.kill!(url)

        failed(url)
        return nil
      end
    end

    #
    # Dequeues a URL that will later be visited.
    #
    # @return [URI::HTTP]
    #   The URL that was at the front of the queue.
    #
    def dequeue
      @queue.shift
    end

    #
    # Determines if the maximum limit has been reached.
    #
    # @return [Boolean]
    #
    # @since 0.6.0
    #
    def limit_reached?
      actual_links_count = @history.length - @skipped_queue.length
      @limit && actual_links_count >= @limit
    end

    def limit_balance
      return unless @limit

      @limit - (@history.length - @skipped_queue.length)
    end

    #
    # Determines if a given URL should be visited.
    #
    # @param [URI::HTTP] url
    #   The URL in question.
    #
    # @return [Boolean]
    #   Specifies whether the given URL should be visited.
    #
    def visit?(url)
      !visited?(url) && valid?(url)
    end

    def valid?(url)
      visit_scheme?(url.scheme) &&
      visit_host?(url.host) &&
      visit_link?(url.to_s) &&
      visit_url?(url) &&
      visit_ext?(url.path) &&
      robot_allowed?(url.to_s)
    end

    #
    # Adds a given URL to the failures list.
    #
    # @param [URI::HTTP] url
    #   The URL to add to the failures list.
    #
    def failed(url)
      @failures << url
      @every_failed_url_blocks.each { |fail_block| fail_block.call(url) }
      return true
    end

  end
end
