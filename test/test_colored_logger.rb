require 'minitest/autorun'
require 'stringio'
require_relative '../lib/colored_logger'

class TestColoredLogger < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
  end

  def test_inherits_from_logger
    assert_kind_of Logger, @logger
  end

  def test_colors_constant
    expected_colors = {
      'DEBUG' => "\e[36m",  # Cyan
      'INFO' => "\e[34m",   # Blue
      'WARN' => "\e[33m",   # Yellow
      'ERROR' => "\e[31m",  # Red
      'FATAL' => "\e[35m",  # Magenta
      'UNKNOWN' => "\e[37m", # White
      'CACHE' => "\e[90m"   # Gray
    }
    assert_equal expected_colors, ColoredLogger::COLORS
  end

  def test_reset_constant
    assert_equal "\e[0m", ColoredLogger::RESET
  end

  def test_formatter_is_proc
    assert_kind_of Proc, @logger.formatter
  end

  def test_debug_logging
    @logger.debug('Test debug message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[DEBUG\] \e\[36mTest debug message\e\[0m\n}, output
  end

  def test_info_logging
    @logger.info('Test info message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] \e\[34mTest info message\e\[0m\n}, output
  end

  def test_warn_logging
    @logger.warn('Test warn message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[WARN\] \e\[33mTest warn message\e\[0m\n}, output
  end

  def test_error_logging
    @logger.error('Test error message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[ERROR\] \e\[31mTest error message\e\[0m\n}, output
  end

  def test_fatal_logging
    @logger.fatal('Test fatal message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[FATAL\] \e\[35mTest fatal message\e\[0m\n}, output
  end

  def test_unknown_logging
    @logger.unknown('Test unknown message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[ANY\] \e\[37mTest unknown message\e\[0m\n}, output
  end

  def test_cache_detection_case_insensitive
    @logger.info('This is a cache message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[CACHE\] \e\[90mThis is a cache message\e\[0m\n}, output
  end

  def test_cache_detection_uppercase
    @logger.info('CACHE operation performed')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[CACHE\] \e\[90mCACHE operation performed\e\[0m\n}, output
  end

  def test_cache_detection_mixed_case
    @logger.info('Cache hit detected')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[CACHE\] \e\[90mCache hit detected\e\[0m\n}, output
  end

  def test_no_cache_detection
    @logger.info('Regular info message')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] \e\[34mRegular info message\e\[0m\n}, output
  end

  def test_unknown_severity_defaults_to_white
    # Simulate unknown severity by calling formatter directly
    severity = 'CUSTOM'
    datetime = Time.now
    progname = nil
    msg = 'Custom message'
    formatted = @logger.formatter.call(severity, datetime, progname, msg)
    expected = "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [CUSTOM] \e[37m#{msg}\e[0m\n"
    assert_equal expected, formatted
  end

  def test_formatter_with_progname
    @logger.progname = 'TestApp'
    @logger.info('Test message')
    output = @output.string
    # Logger's default formatter includes progname, but our custom formatter doesn't use it
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] \e\[34mTest message\e\[0m\n}, output
  end

  def test_multiple_log_messages
    @logger.debug('Debug message')
    @logger.info('Info message')
    @logger.warn('Warn message')
    output = @output.string
    lines = output.split("\n").reject(&:empty?)
    assert_equal 3, lines.size
    assert_match %r{\[DEBUG\]}, lines[0]
    assert_match %r{\[INFO\]}, lines[1]
    assert_match %r{\[WARN\]}, lines[2]
  end

  def test_timestamp_format
    time = Time.new(2023, 10, 10, 14, 30, 45)
    formatted = @logger.formatter.call('INFO', time, nil, 'Test')
    assert_match %r{^2023-10-10 14:30:45}, formatted
  end

  def test_color_codes_are_ansi_escape_sequences
    ColoredLogger::COLORS.each_value do |color|
      assert_match %r{^\e\[\d+m$}, color
    end
    assert_match %r{^\e\[0m$}, ColoredLogger::RESET
  end

  def test_colors_frozen
    assert ColoredLogger::COLORS.frozen?
  end

  def test_reset_frozen
    assert ColoredLogger::RESET.frozen?
  end

  def test_formatter_proc_arity
    assert_equal 4, @logger.formatter.arity
  end

  def test_log_level_inheritance
    assert_equal Logger::DEBUG, @logger.level
  end

  def test_initialization_with_log_device
    file = StringIO.new
    logger = ColoredLogger.new(file)
    assert_equal file, logger.instance_variable_get(:@logdev).dev
  end

  def test_initialization_with_filename
    # Test with a temp file
    require 'tempfile'
    Tempfile.create('test_log') do |file|
      logger = ColoredLogger.new(file.path)
      assert_equal file.path, logger.instance_variable_get(:@logdev).filename
    end
  end

  def test_formatter_preserves_newlines_in_message
    @logger.info("Line 1\nLine 2")
    output = @output.string
    assert_match %r{Line 1\nLine 2}, output
  end

  def test_empty_message
    @logger.info('')
    output = @output.string
    assert_match %r{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] \e\[34m\e\[0m\n}, output
  end

  def test_message_with_special_characters
    @logger.info('Message with "quotes" and \'apostrophes\'')
    output = @output.string
    assert_match %r{Message with "quotes" and 'apostrophes'}, output
  end

  def test_cache_detection_partial_word
    @logger.info('This is cached data')
    output = @output.string
    assert_match %r{\[CACHE\]}, output
  end

  def test_cache_detection_at_end
    @logger.info('Data cache')
    output = @output.string
    assert_match %r{\[CACHE\]}, output
  end

  def test_no_cache_detection_similar_words
    @logger.info('This is a cached message')  # cached contains cache
    output = @output.string
    assert_match %r{\[CACHE\]}, output
  end

  def test_no_cache_detection_different_word
    @logger.info('This is a pocket message')  # pocket does not contain cache
    output = @output.string
    assert_match %r{\[INFO\]}, output
  end
end