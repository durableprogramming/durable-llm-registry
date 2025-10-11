require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'nokogiri'
require_relative '../lib/fetchers/opencode'
require_relative '../lib/colored_logger'

class TestOpencode < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @fetcher = Fetchers::Opencode.new(logger: @logger)
    @logger.level = Logger::INFO  # Override after initialization to capture info messages
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    fetcher = Fetchers::Opencode.new(logger: custom_logger)
    assert_equal custom_logger, fetcher.logger
    assert_equal Logger::WARN, custom_logger.level
  end

  def test_initialization_with_default_logger
    fetcher = Fetchers::Opencode.new
    assert_kind_of ColoredLogger, fetcher.logger
    assert_equal Logger::WARN, fetcher.logger.level
  end

  def test_class_fetch_method
    mock_models = [{ name: 'Test Model', api_name: 'test-model' }]
    fetcher_instance = Fetchers::Opencode.new(logger: @logger)
    fetcher_instance.stub :fetch, mock_models do
      Fetchers::Opencode.stub :new, fetcher_instance do
        result = Fetchers::Opencode.fetch(logger: @logger)
        assert_kind_of Array, result
        refute_empty result
      end
    end
  end

  def test_fetch_with_empty_models_returns_empty_array
    @fetcher.stub :fetch_models, [] do
      result = @fetcher.fetch
      assert_empty result
    end
  end

  def test_fetch_combines_models_and_pricing
    models = [
      { name: 'Model 1', api_name: 'model-1' },
      { name: 'Model 2', api_name: 'model-2' }
    ]
    pricing = {
      'model-1' => { input_price: 1.0, output_price: 2.0 },
      'model-2' => { input_price: 3.0, output_price: 4.0 }
    }

    @fetcher.stub :fetch_models, models do
      @fetcher.stub :fetch_pricing, pricing do
        result = @fetcher.fetch
        assert_equal 2, result.size
        assert_equal 'Model 1', result[0][:name]
        assert_equal 'model-1', result[0][:api_name]
        assert_equal 1.0, result[0][:input_price]
        assert_equal 2.0, result[0][:output_price]
        assert_equal 'Model 2', result[1][:name]
        assert_equal 'model-2', result[1][:api_name]
        assert_equal 3.0, result[1][:input_price]
        assert_equal 4.0, result[1][:output_price]
      end
    end
  end

  def test_fetch_handles_exceptions_and_returns_empty_array
    @fetcher.stub :fetch_models, -> { raise StandardError.new('Test error') } do
      result = @fetcher.fetch
      assert_empty result
      assert_match %r{Failed to fetch OpenCode Zen data}, @output.string
    end
  end

  def test_fetch_logs_success_message
    models = [{ name: 'Test Model', api_name: 'test' }]
    pricing = {}

    @fetcher.stub :fetch_models, models do
      @fetcher.stub :fetch_pricing, pricing do
        @fetcher.fetch
        assert_match %r{Successfully fetched 1 models}, @output.string
      end
    end
  end

  def test_fetch_models_parses_valid_table_data
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model ID</th><th>API Name</th><th>Endpoint</th></tr>
        <tr><td>GPT 5</td><td>gpt-5</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
        <tr><td>Claude Sonnet 4</td><td>claude-sonnet-4</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 2, models.size
      assert_equal 'GPT 5', models[0][:name]
      assert_equal 'gpt-5', models[0][:api_name]
      assert_equal 'https://api.opencode.ai/v1/chat/completions', models[0][:endpoint]
      assert_equal 'Claude Sonnet 4', models[1][:name]
      assert_equal 'claude-sonnet-4', models[1][:api_name]
    end
  end

  def test_fetch_models_skips_header_rows
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model ID</th><th>API Name</th><th>Endpoint</th></tr>
        <tr><td>Model ID</td><td>API Name</td><td>Endpoint</td></tr>
        <tr><td>GPT 5</td><td>gpt-5</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 1, models.size
      assert_equal 'GPT 5', models[0][:name]
    end
  end

  def test_fetch_models_handles_missing_table_headers
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Name</th><th>Value</th></tr>
        <tr><td>Model</td><td>Data</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_empty models
    end
  end

  def test_fetch_models_deduplicates_by_api_name
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model ID</th><th>API Name</th><th>Endpoint</th></tr>
        <tr><td>GPT 5</td><td>gpt-5</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
        <tr><td>GPT 5 Duplicate</td><td>gpt-5</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 1, models.size
      assert_equal 'GPT 5', models[0][:name]
    end
  end

  def test_fetch_models_logs_extraction_count
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model ID</th><th>API Name</th><th>Endpoint</th></tr>
        <tr><td>GPT 5</td><td>gpt-5</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      @fetcher.send(:fetch_models)
      assert_match %r{Extracted 1 unique models}, @output.string
    end
  end

  def test_fetch_models_handles_parse_errors_gracefully
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model ID</th><th>API Name</th><th>Endpoint</th></tr>
        <tr><td>GPT 5</td><td>gpt-5</td><td>https://api.opencode.ai/v1/chat/completions</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      @fetcher.stub :safe_text, ->(_) { raise StandardError.new('Parse error') } do
        models = @fetcher.send(:fetch_models)
        assert_empty models
        assert_match %r{Error parsing models table}, @output.string
      end
    end
  end

  def test_fetch_models_returns_empty_on_fetch_html_failure
    @fetcher.stub :fetch_html, nil do
      models = @fetcher.send(:fetch_models)
      assert_empty models
    end
  end

  def test_fetch_models_handles_exceptions_and_returns_empty
    @fetcher.stub :fetch_html, -> { raise StandardError.new('Fetch error') } do
      models = @fetcher.send(:fetch_models)
      assert_empty models
      assert_match %r{Error in fetch_models}, @output.string
    end
  end

  def test_fetch_pricing_parses_valid_table_data
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model</th><th>Input</th><th>Output</th><th>Cached Read</th><th>Cached Write</th></tr>
        <tr><td>GPT 5</td><td>$3.00</td><td>$15.00</td><td>$1.50</td><td>$3.00</td></tr>
        <tr><td>Claude Sonnet 4</td><td>$1.00</td><td>$5.00</td><td>-</td><td>-</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      pricing = @fetcher.send(:fetch_pricing)
      assert_equal 2, pricing.size
      assert_equal 3.0, pricing['gpt-5'][:input_price]
      assert_equal 15.0, pricing['gpt-5'][:output_price]
      assert_equal 1.5, pricing['gpt-5'][:cache_hit_price]
      assert_equal 3.0, pricing['gpt-5'][:cache_write_price]
      assert_equal 1.0, pricing['claude-sonnet-4'][:input_price]
      assert_equal 5.0, pricing['claude-sonnet-4'][:output_price]
    end
  end

  def test_fetch_pricing_skips_header_rows
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model</th><th>Input</th><th>Output</th></tr>
        <tr><td>Model</td><td>Input</td><td>Output</td></tr>
        <tr><td>GPT 5</td><td>$3.00</td><td>$15.00</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      pricing = @fetcher.send(:fetch_pricing)
      assert_equal 1, pricing.size
      assert_equal 3.0, pricing['gpt-5'][:input_price]
    end
  end

  def test_fetch_pricing_handles_missing_pricing_headers
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Name</th><th>Value</th></tr>
        <tr><td>Setting</td><td>Enabled</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      pricing = @fetcher.send(:fetch_pricing)
      assert_empty pricing
    end
  end

  def test_fetch_pricing_logs_extraction_count
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model</th><th>Input</th><th>Output</th></tr>
        <tr><td>GPT 5</td><td>$3.00</td><td>$15.00</td></tr>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      @fetcher.send(:fetch_pricing)
      assert_match %r{Extracted pricing for 1 models}, @output.string
    end
  end

  def test_fetch_pricing_handles_parse_errors_gracefully
    html = <<-HTML
    <html><body>
      <table>
        <tr><th>Model</th><th>Input</th><th>Output</th></tr>
        <tr><td>GPT 5</td><td>$3.00</td><td>$15.00</td></tr>
      </table>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      @fetcher.stub :extract_pricing_info, ->(_) { raise StandardError.new('Parse error') } do
        pricing = @fetcher.send(:fetch_pricing)
        assert_empty pricing
        assert_match %r{Error parsing pricing row}, @output.string
      end
    end
  end

  def test_fetch_pricing_returns_empty_on_fetch_html_failure
    @fetcher.stub :fetch_html, nil do
      pricing = @fetcher.send(:fetch_pricing)
      assert_empty pricing
    end
  end

  def test_fetch_pricing_handles_exceptions_and_returns_empty
    @fetcher.stub :fetch_html, -> { raise StandardError.new('Fetch error') } do
      pricing = @fetcher.send(:fetch_pricing)
      assert_empty pricing
      assert_match %r{Error in fetch_pricing}, @output.string
    end
  end

  def test_extract_pricing_info_basic_extraction
    cells = [
      mock_cell('GPT 5'),
      mock_cell('$3.00'),
      mock_cell('$15.00'),
      mock_cell('$1.50'),
      mock_cell('$3.00')
    ]

    pricing = @fetcher.send(:extract_pricing_info, cells)
    assert_equal 3.0, pricing[:input_price]
    assert_equal 15.0, pricing[:output_price]
    assert_equal 1.5, pricing[:cache_hit_price]
    assert_equal 3.0, pricing[:cache_write_price]
  end

  def test_extract_pricing_info_handles_missing_cells
    cells = [
      mock_cell('GPT 5'),
      mock_cell('$3.00'),
      mock_cell('$15.00')
    ]

    pricing = @fetcher.send(:extract_pricing_info, cells)
    assert_equal 3.0, pricing[:input_price]
    assert_equal 15.0, pricing[:output_price]
  end

  def test_extract_pricing_info_skips_invalid_prices
    cells = [
      mock_cell('GPT 5'),
      mock_cell('-'),
      mock_cell('$15.00')
    ]

    pricing = @fetcher.send(:extract_pricing_info, cells)
    assert_nil pricing[:input_price]
    assert_equal 15.0, pricing[:output_price]
  end

  def test_extract_pricing_info_handles_errors_gracefully
    cells = [
      mock_cell('GPT 5'),
      mock_cell('$3.00'),
      mock_cell('$15.00')
    ]

    @fetcher.stub :extract_price, ->(_) { raise StandardError.new('Extract error') } do
      pricing = @fetcher.send(:extract_pricing_info, cells)
      assert_empty pricing
      assert_match %r{Error extracting pricing info}, @output.string
    end
  end

  def test_fetch_html_successful_request
    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, true)
    mock_response.expect(:body, '<html><body>Test</body></html>')

    connection_mock = Minitest::Mock.new
    connection_mock.expect(:get, mock_response, ['https://test.com'])

    @fetcher.stub :connection, connection_mock do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_kind_of Nokogiri::HTML::Document, doc
      assert_match %r{Test}, doc.text
    end
  end

  def test_fetch_html_handles_http_error
    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, false)
    mock_response.expect(:status, 404)

    connection_mock = Minitest::Mock.new
    connection_mock.expect(:get, mock_response, ['https://test.com'])

    @fetcher.stub :connection, connection_mock do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_nil doc
      assert_match %r{HTTP 404 for test page}, @output.string
    end
  end

  def test_fetch_html_handles_empty_response_body
    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, true)
    mock_response.expect(:body, '')

    connection_mock = Minitest::Mock.new
    connection_mock.expect(:get, mock_response, ['https://test.com'])

    @fetcher.stub :connection, connection_mock do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_nil doc
      assert_match %r{Empty response body for test page}, @output.string
    end
  end

  def test_fetch_html_handles_nil_response_body
    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, true)
    mock_response.expect(:body, nil)

    connection_mock = Minitest::Mock.new
    connection_mock.expect(:get, mock_response, ['https://test.com'])

    @fetcher.stub :connection, connection_mock do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_nil doc
      assert_match %r{Empty response body for test page}, @output.string
    end
  end

  def test_fetch_html_handles_invalid_html
    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, true)
    mock_response.expect(:body, '<html><invalid>')

    connection_mock = Minitest::Mock.new
    connection_mock.expect(:get, mock_response, ['https://test.com'])

    @fetcher.stub :connection, connection_mock do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      # Nokogiri can parse invalid HTML, so it should return a document
      assert_kind_of Nokogiri::HTML::Document, doc
      refute_nil doc.at('invalid')
    end
  end

  def test_fetch_html_handles_timeout_with_retry
    @fetcher.stub :connection, -> { raise Faraday::TimeoutError } do
      @fetcher.stub :sleep, nil do
        doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
        assert_nil doc
        assert_match %r{Max retries reached for test page}, @output.string
      end
    end
  end

  def test_fetch_html_handles_faraday_errors
    @fetcher.stub :connection, -> { raise Faraday::Error.new('Network error') } do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_nil doc
      assert_match %r{Failed to fetch test page: Network error}, @output.string
    end
  end

  def test_fetch_html_handles_unexpected_errors
    @fetcher.stub :connection, -> { raise StandardError.new('Unexpected') } do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_nil doc
      assert_match %r{Unexpected error fetching test page: StandardError - Unexpected}, @output.string
    end
  end

  def test_connection_returns_http_cache_instance
    cache = @fetcher.send(:connection)
    assert_kind_of HttpCache, cache
  end

  def test_extract_pricing_info_compacts_results
    cells = [
      mock_cell('GPT 5'),
      mock_cell('$0.00'),
      mock_cell('$15.00')
    ]

    pricing = @fetcher.send(:extract_pricing_info, cells)
    assert_nil pricing[:input_price]  # 0.0 is not > 0
    assert_equal 15.0, pricing[:output_price]
  end

  def test_safe_text_normal_text
    doc = Nokogiri::HTML('<div>Test text</div>')
    element = doc.at('div')
    assert_equal 'Test text', @fetcher.send(:safe_text, element)
  end

  def test_safe_text_with_whitespace
    doc = Nokogiri::HTML("<div>  Test\n  text  </div>")
    element = doc.at('div')
    assert_equal 'Test text', @fetcher.send(:safe_text, element)
  end

  def test_safe_text_nil_element
    assert_equal '', @fetcher.send(:safe_text, nil)
  end

  def test_safe_text_handles_errors
    element = Object.new
    def element.text
      raise StandardError.new('Text error')
    end
    assert_equal '', @fetcher.send(:safe_text, element)
    assert_match %r{Error extracting text}, @output.string
  end

  def test_header_row_detects_model_header
    assert @fetcher.send(:header_row?, 'Model ID')
    assert @fetcher.send(:header_row?, 'model id')
    assert @fetcher.send(:header_row?, 'MODEL ID')
  end

  def test_header_row_returns_false_for_data
    refute @fetcher.send(:header_row?, 'GPT 5')
    refute @fetcher.send(:header_row?, 'Some other text')
  end

  def test_extract_price_valid_prices
    assert_equal 3.0, @fetcher.send(:extract_price, '$3.00')
    assert_equal 1.5, @fetcher.send(:extract_price, '$1.50')
    assert_equal 0.0, @fetcher.send(:extract_price, 'Free')
    assert_equal 0.0, @fetcher.send(:extract_price, 'free')
  end

  def test_extract_price_invalid_prices
    assert_nil @fetcher.send(:extract_price, nil)
    assert_nil @fetcher.send(:extract_price, '')
    assert_nil @fetcher.send(:extract_price, '-')
    assert_nil @fetcher.send(:extract_price, 'N/A')
    assert_nil @fetcher.send(:extract_price, '$0')
    assert_nil @fetcher.send(:extract_price, '$0.00')
  end

  def test_extract_price_with_commas_and_spaces
    assert_equal 1500.0, @fetcher.send(:extract_price, '$1,500')
    assert_equal 1.5, @fetcher.send(:extract_price, '$ 1 . 50 ')
  end

  def test_extract_price_handles_errors
    assert_nil @fetcher.send(:extract_price, nil)
    assert_nil @fetcher.send(:extract_price, '')
  end

  def test_extract_api_name_from_model_name_mapped_names
    test_cases = {
      'GPT 5' => 'gpt-5',
      'GPT 5 Codex' => 'gpt-5-codex',
      'Claude Sonnet 4.5' => 'claude-sonnet-4-5',
      'Claude Sonnet 4' => 'claude-sonnet-4',
      'Claude Haiku 3.5' => 'claude-3-5-haiku',
      'Claude Opus 4.1' => 'claude-opus-4-1',
      'Qwen3 Coder 480B' => 'qwen3-coder',
      'Grok Code Fast 1' => 'grok-code',
      'Kimi K2' => 'kimi-k2'
    }

    test_cases.each do |model_name, expected_api_name|
      api_name = @fetcher.send(:extract_api_name_from_model_name, model_name)
      assert_equal expected_api_name, api_name, "Failed for #{model_name}"
    end
  end

  def test_extract_api_name_from_model_name_fallback
    api_name = @fetcher.send(:extract_api_name_from_model_name, 'Unknown Model Name')
    assert_equal 'unknown-model-name', api_name
  end

  def test_extract_api_name_from_model_name_handles_edge_cases
    assert_nil @fetcher.send(:extract_api_name_from_model_name, nil)
    assert_nil @fetcher.send(:extract_api_name_from_model_name, '')
    api_name = @fetcher.send(:extract_api_name_from_model_name, 'Simple')
    assert_equal 'simple', api_name
  end

  def test_extract_api_name_from_model_name_handles_errors
    # Test error handling by passing invalid input that causes errors
    api_name = @fetcher.send(:extract_api_name_from_model_name, nil)
    assert_nil api_name
  end

  def test_constants
    assert_equal 'https://opencode.ai/docs/zen/', Fetchers::Opencode::MODELS_URL
    assert_equal 30, Fetchers::Opencode::TIMEOUT
    assert_equal 3, Fetchers::Opencode::MAX_RETRIES
    assert_equal 2, Fetchers::Opencode::RETRY_DELAY
  end

  def test_fetch_error_inheritance
    assert_kind_of StandardError, Fetchers::Opencode::FetchError.new
  end

  private

  def mock_cell(text)
    # Create a simple object that responds to text method
    Object.new.tap do |cell|
      def cell.text
        @text
      end
      cell.instance_variable_set(:@text, text)
    end
  end
end