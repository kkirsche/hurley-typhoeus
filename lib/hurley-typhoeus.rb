require 'typhoeus'

module HurleyTyphoeus
  VERSION = '0.0.1'
  DEFAULT_CHUNK_SIZE = 1_048_576

  class Connection
    def initialize(options = nil)
      @options = options || {}
    end

    def call(request)
      opts = {}
      configure_ssl(opts, request.ssl_options) if request.url.scheme == Hurley::HTTPS
      configure_request(opts, request.options)
      configure_proxy(opts, request.options)

      Hurley::Response.new(request) do |res|
        typhoeus = perform(res, opts)
        res.status_code = typhoeus.code.to_i
        res.header.update(typhoeus.headers)
        body = typhoeus.body.to_s
        res.receive_body(body) if !body.empty?
      end
    end

    def perform(res, options)
      req = res.request

      req_options = {
        :method  => req.verb,
        :headers => req.header,
        :body => req.body,
        :followlocation => true,
        :connecttimeout => 60
      }

      req_options.merge! options

      request = Typhoeus::Request.new(req.url.to_s, req_options)

      request.on_complete do |response|
        if response.timed_out?
          raise Hurley::Timeout, 'The request timed out.'
        end

        # case response.curl_return_code
        # when 0
        #   # Everything OK
        # when 60
        #   raise Hurley::SSLError, response.curl_error_message
        # else
        #   raise Hurley::ConnectionFailed, response.curl_error_message
        # end
      end

      if body = req.body_io
        body.read(HurleyTyphoeus::DEFAULT_CHUNK_SIZE).to_s
      end

      response = request.run
      response
    rescue ::Typhoeus::Errors::TyphoeusError => err
      raise Hurley::ConnectionFailed, err
    end

    def configure_ssl(opts, ssl)
      opts[:ssl_verifypeer] = !ssl.skip_verification?
      opts[:ssl_ca_path] = ssl.ca_path if ssl.ca_path
      opts[:ssl_ca_file] = ssl.ca_file if ssl.ca_file

      opts[:certificate_path] = ssl.client_cert_path if ssl.client_cert_path
      opts[:certificate] = ssl.client_cert if ssl.client_cert

      opts[:private_key] = ssl.private_key if ssl.private_key
      opts[:private_key_path] = ssl.private_key_path if ssl.private_key_path
      opts[:private_key_pass] = ssl.private_key_pass if ssl.private_key_pass

      # https://github.com/jruby/jruby-ossl/issues/19
      # opts[:nonblock] = false
    end

    def configure_request(opts, options)
      if t = options.timeout
        opts[:connecttimeout] = t
        opts[:timeout] = t
      end

      if t = options.open_timeout
        opts[:connecttimeout] = t
        opts[:timeout] = t
      end
    end

    def configure_proxy(opts, options)
      return unless proxy = options.proxy
      opts[:proxy] = {
        :proxy => "#{proxy.scheme}://#{proxy.host}:#{proxy.port}",
        :proxyuserpwd => "#{proxy.user}:#{proxy.password}"
      }
    end
  end
end
