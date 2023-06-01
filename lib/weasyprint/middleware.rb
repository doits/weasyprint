# frozen_string_literal: true

class WeasyPrint
  class Middleware
    def initialize(app, options = {}, conditions = {})
      @app        = app
      @options    = options
      @conditions = conditions
    end

    def call(env)
      @request    = Rack::Request.new(env)
      @render_pdf = false
      @caching    = @conditions.delete(:caching) { false }

      request_to_render_as_pdf(env) if render_as_pdf?
      status, headers, response = @app.call(env)

      if rendering_pdf? && headers['content-type'] =~ %r{text/html|application/xhtml\+xml}
        body = response.respond_to?(:body) ? response.body : response.join
        body = body.join if body.is_a?(Array)
        body = WeasyPrint.new(translate_paths(body, env), @options).to_pdf
        response = [body]

        if headers['weasyprint-save-pdf']
          begin
            File.binwrite(headers['weasyprint-save-pdf'], body)
          rescue StandardError
            nil
          end
          headers.delete('weasyprint-save-pdf')
        end

        unless @caching
          # Do not cache PDFs
          headers.delete('etag')
          headers.delete('cache-control')
        end

        headers['content-length']         = (body.respond_to?(:bytesize) ? body.bytesize : body.size).to_s
        headers['content-type']           = 'application/pdf'
      end

      [status, headers, response]
    end

    private

    # Change relative paths to absolute
    def translate_paths(body, env)
      # Host with protocol
      root = WeasyPrint.configuration.root_url || "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}/"

      body.gsub(%r{(href|src)=(['"])/([^/]([^"']*|[^"']*))['"]}, '\1=\2' + root + '\3\2')
    end

    def rendering_pdf?
      @render_pdf
    end

    def render_as_pdf?
      request_path_is_pdf = @request.path.match(/\.pdf$/)

      if request_path_is_pdf && @conditions[:only]
        rules = [@conditions[:only]].flatten
        rules.any? do |pattern|
          test_condition(pattern, @request.path)
        end
      elsif request_path_is_pdf && @conditions[:except]
        rules = [@conditions[:except]].flatten
        rules.none? do |pattern|
          test_condition(pattern, @request.path)
        end
      else
        request_path_is_pdf
      end
    end

    def test_condition(pattern, path)
      if pattern.is_a?(Regexp)
        path =~ pattern
      else
        path[0, pattern.length] == pattern
      end
    end

    def request_to_render_as_pdf(env)
      @render_pdf = true

      path = @request.path.sub(/\.pdf$/, '')
      path = path.sub(@request.script_name, '')

      %w[PATH_INFO REQUEST_URI].each { |e| env[e] = path }

      env['HTTP_ACCEPT'] = concat(env['HTTP_ACCEPT'], Rack::Mime.mime_type('.html'))
      env['Rack-Middleware-WeasyPrint'] = 'true'
    end

    def concat(accepts, type)
      (accepts || '').split(',').unshift(type).compact.join(',')
    end
  end
end
