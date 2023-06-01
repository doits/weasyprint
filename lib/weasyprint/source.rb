# frozen_string_literal: true

class WeasyPrint
  class Source
    def initialize(url_file_or_html)
      @source = url_file_or_html
    end

    def url?
      @source.is_a?(String) && @source.start_with?('http')
    end

    def file?
      @source.is_a?(File)
    end

    def html?
      !(url? || file?)
    end

    def to_s
      file? ? @source.path : @source
    end
  end
end
