require 'faraday'
require 'uri_template'

module Sawyer
  class Agent
    NO_BODY = Set.new([:get, :head])

    class << self
      attr_writer :serializer
    end

    def self.serializer
      @serializer ||= begin
        require File.expand_path("../serializer", __FILE__)
        require 'yajl'
        Serializer.new(Yajl)
      end
    end

    # Agents handle making the requests, and passing responses to
    # Sawyer::Response.
    #
    # endpoint - String URI of the API entry point.
    # options  - Hash of options.
    #            :faraday    - Optional Faraday::Connection to use.
    #            :serializer - Optional serializer Class.  Defaults to
    #                          self.serializer_class.
    #
    # Yields the Faraday::Connection if a block is given.
    def initialize(endpoint, options = nil)
      @endpoint = endpoint
      @conn = (options && options[:faraday]) || Faraday.new(endpoint)
      @serializer = (options && options[:serializer]) || self.class.serializer
      yield @conn if block_given?
    end

    # Public: Retains a reference to the root relations of the API.
    #
    # Returns a Sawyer::Relation::Map.
    def rels
      @rels ||= root.data.rels
    end

    # Public: Retains a reference to the root response of the API.
    #
    # Returns a Sawyer::Response.
    def root
      @root ||= start
    end

    # Public: Hits the root of the API to get the initial actions.
    #
    # Returns a Sawyer::Response.
    def start
      call :get, @endpoint
    end

    # Makes a request through Faraday.
    #
    # method  - The Symbol name of an HTTP method.
    # url     - The String URL to access.  This can be relative to the Agent's
    #           endpoint.
    # data    - The Optional Hash or Resource body to be sent.  :get or :head
    #           requests can have no body, so this can be the options Hash
    #           instead.
    # options - Hash of option to configure the API request.
    #           :headers - Hash of API headers to set.
    #           :query   - Hash of URL query params to set.
    #
    # Returns a Sawyer::Response.
    def call(method, url, data = nil, options = nil)
      if NO_BODY.include?(method)
        options ||= data
        data      = nil
      end

      options ||= {}
      url = expand_url(url, options[:uri])
      started = nil
      res = @conn.send method, url do |req|
        req.body = encode_body(data) if data
        if params = options[:query]
          req.params.update params
        end
        if headers = options[:headers]
          req.headers.update headers
        end
        started = Time.now
      end
      res.env[:sawyer_started] = started
      res.env[:sawyer_ended] = Time.now

      Response.new self, res
    end

    # Encodes an object to a string for the API request.
    #
    # data - The Hash or Resource that is being sent.
    #
    # Returns a String.
    def encode_body(data)
      @serializer.encode(data)
    end

    # Decodes a String response body to a resource.
    #
    # str - The String body from the response.
    #
    # Returns an Object resource (Hash by default).
    def decode_body(str)
      @serializer.decode(str)
    end

    def expand_url(url, options = nil)
      tpl = url.respond_to?(:expand) ? url : URITemplate.new(url.to_s)
      expand = tpl.method(:expand)
      options ? expand.call(options) : expand.call
    end

    def inspect
      %(<#{self.class} #{@endpoint}>)
    end
  end
end

