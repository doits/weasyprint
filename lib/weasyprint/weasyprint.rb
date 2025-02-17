# frozen_string_literal: true

require 'English'

require 'shellwords'

class WeasyPrint
  class NoExecutableError < StandardError
    def initialize
      msg  = "No weasyprint executable found at #{WeasyPrint.configuration.weasyprint}\n"
      msg << '>> Please install weasyprint - https://doc.courtbouillon.org/weasyprint/stable/'
      super(msg)
    end
  end

  class ImproperSourceError < StandardError
    def initialize(msg)
      super("Improper Source: #{msg}")
    end
  end

  attr_accessor :source, :styles, :stylesheets
  attr_reader :options

  def initialize(url_file_or_html, options = {})
    @source = Source.new(url_file_or_html)

    @stylesheets = []
    @styles = []

    @options = WeasyPrint.configuration.default_options.merge(options)
    @options = normalize_options(@options)

    raise NoExecutableError unless File.exist?(WeasyPrint.configuration.weasyprint)
  end

  def command(path = nil)
    args = [executable]
    args += @options.to_a.flatten.compact

    args << if @source.html?
              '-' # Get HTML from stdin
            else
              @source.to_s
            end

    args << (path || '-') # Write to file or stdout

    args.shelljoin
  end

  def executable
    default = WeasyPrint.configuration.weasyprint
    return default unless %r{^/}.match?(default) # its not a path, so nothing we can do

    if File.exist?(default)
      default
    else
      default.split('/').last
    end
  end

  def to_pdf(path = nil)
    append_stylesheets

    invoke = command(path)

    result = IO.popen(invoke, 'wb+') do |pdf|
      pdf.puts(@source.to_s) if @source.html?
      pdf.close_write
      pdf.gets(nil)
    end
    result = File.read(path) if path

    # $? is thread safe per http://stackoverflow.com/questions/2164887/thread-safe-external-process-in-ruby-plus-checking-exitstatus
    if !result || result.bytesize < 100 || !successful?($CHILD_STATUS)
      raise("command failed (exitstatus=#{$CHILD_STATUS.exitstatus}): #{invoke}")
    end

    result
  end

  def to_file(path)
    to_pdf(path)
    File.new(path)
  end

  protected

  REPEATABLE_OPTIONS = %w[].freeze

  def append_stylesheets
    raise ImproperSourceError, 'Stylesheets may only be added to an HTML source' if stylesheets.any? && !@source.html?

    custom_styles = stylesheets.map { |stylesheet| File.read(stylesheet) }

    (custom_styles + styles).each do |style|
      @source =
        if @source.to_s.include?('</head>')
          Source.new(@source.to_s.gsub(%r{(</head>)}) { |s| "<style>#{style}</style>" + s })
        else
          Source.new("<style>#{style}</style>" + @source.to_s)
        end
    end
  end

  def normalize_options(options)
    normalized_options = {}

    options.each do |key, value|
      next unless value

      # The actual option for weasyprint
      normalized_key = "--#{normalize_arg key}"

      # If the option is repeatable, attempt to normalize all values
      if REPEATABLE_OPTIONS.include? normalized_key
        normalize_repeatable_value(value) do |normalized_key_piece, normalized_value|
          normalized_options[[normalized_key, normalized_key_piece]] = normalized_value
        end
      else # Otherwise, just normalize it like usual
        normalized_options[normalized_key] = normalize_value(value)
      end
    end

    normalized_options
  end

  def normalize_arg(arg)
    arg.to_s.downcase.gsub(/[^a-z0-9]/, '-')
  end

  def normalize_value(value)
    case value
    when TrueClass, 'true' # ie, ==true, see http://www.ruby-doc.org/core-1.9.3/TrueClass.html
      nil
    when Hash
      value.to_a.flatten.filter_map { |x| normalize_value(x) }
    when Array
      value.flatten.collect(&:to_s)
    else
      value.to_s
    end
  end

  def normalize_repeatable_value(value)
    case value
    when Hash, Array
      value.each do |(key, value)|
        yield [normalize_value(key), normalize_value(value)]
      end
    else
      [normalize_value(value), '']
    end
  end

  def successful?(status)
    status.success?
  end
end
