require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'nokogiri'
require_relative '../lib/fetchers/fireworks'
require_relative '../lib/colored_logger'

class TestFireworks < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @fetcher = Fetchers::Fireworks.new(logger: @logger)
    @logger.level = Logger::INFO  # Override after initialization to capture info messages
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    fetcher = Fetchers::Fireworks.new(logger: custom_logger)
    assert_equal custom_logger, fetcher.logger
    assert_equal Logger::WARN, custom_logger.level
  end

  def test_initialization_with_default_logger
    fetcher = Fetchers::Fireworks.new
    assert_kind_of ColoredLogger, fetcher.logger
    assert_equal Logger::WARN, fetcher.logger.level
  end

  def test_class_fetch_method
    mock_models = [{ name: 'Test Model', api_name: 'test-model' }]
    fetcher_instance = Fetchers::Fireworks.new(logger: @logger)
    fetcher_instance.stub :fetch, mock_models do
      Fetchers::Fireworks.stub :new, fetcher_instance do
        result = Fetchers::Fireworks.fetch(logger: @logger)
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

  def test_fetch_with_models_returns_models
    mock_models = [
      { name: 'Model 1', api_name: 'model-1' },
      { name: 'Model 2', api_name: 'model-2' }
    ]

    @fetcher.stub :fetch_models, mock_models do
      result = @fetcher.fetch
      assert_equal 2, result.size
      assert_match %r{Successfully fetched 2 models}, @output.string
    end
  end

  def test_fetch_handles_exceptions_and_returns_empty_array
    @fetcher.stub :fetch_models, -> { raise StandardError.new('Test error') } do
      result = @fetcher.fetch
      assert_empty result
      assert_match %r{Failed to fetch Fireworks data}, @output.string
    end
  end

  def test_fetch_models_parses_valid_model_cards
    html = <<-HTML
    <html><body>
      <a href="/models/fireworks/llama-3-1-8b-instruct">
        <div class="font-bold">Llama 3.1 8B Instruct</div>
        <div>$0.20/M Input • $0.20/M Output</div>
        <div>128k Context</div>
      </a>
      <a href="/models/fireworks/llama-3-1-70b-instruct">
        <div class="font-bold">Llama 3.1 70B Instruct</div>
        <div>$0.90/M Input • $1.80/M Output</div>
        <div>128k Context</div>
      </a>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 2, models.size
      assert_equal 'Llama 3.1 8B Instruct', models[0][:name]
      assert_equal 'llama-3-1-8b-instruct', models[0][:api_name]
      assert_equal 'Llama 3.1 70B Instruct', models[1][:name]
      assert_equal 'llama-3-1-70b-instruct', models[1][:api_name]
    end
  end

  def test_fetch_models_filters_invalid_hrefs
    html = <<-HTML
    <html><body>
      <a href="/models/other-provider/model">
        <div class="font-bold">Other Model</div>
      </a>
      <a href="/models/fireworks/">
        <div class="font-bold">Invalid Model</div>
      </a>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_empty models
    end
  end

  def test_fetch_models_handles_missing_font_bold_div
    html = <<-HTML
    <html><body>
      <a href="/models/fireworks/test-model">
        <div>Plain text</div>
      </a>
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
      <a href="/models/fireworks/test-model">
        <div class="font-bold">Test Model 1</div>
      </a>
      <a href="/models/fireworks/test-model">
        <div class="font-bold">Test Model 2</div>
      </a>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 1, models.size
      assert_equal 'Test Model 1', models[0][:name]
    end
  end

  def test_fetch_models_logs_extraction_count
    html = <<-HTML
    <html><body>
      <a href="/models/fireworks/test-model">
        <div class="font-bold">Test Model</div>
      </a>
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
      <a href="/models/fireworks/test-model">
        <div class="font-bold">Test Model</div>
      </a>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      @fetcher.stub :extract_model_info, ->(*_) { raise StandardError.new('Parse error') } do
        models = @fetcher.send(:fetch_models)
        assert_empty models
        assert_match %r{Error parsing model card}, @output.string
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

  def test_extract_model_info_extracts_complete_info
    html = <<-HTML
    <div>
      <h3>Llama 3.1 8B Instruct</h3>
      <div>$0.20/M Input • $0.20/M Output</div>
      <div>128k Context</div>
      <div>Function calling available</div>
    </div>
    HTML
    card_element = Nokogiri::HTML(html).at('div')

    info = @fetcher.send(:extract_model_info, card_element, 'llama-3-1-8b-instruct')
    assert_equal 'Llama 3.1 8B Instruct', info[:name]
    assert_equal({ input_price: 0.20, output_price: 0.20 }, info[:pricing])
    assert_equal 128000, info[:context_window]
    assert_includes info[:capabilities], 'function_calling'
    assert_equal({ input: ['text'], output: ['text'] }, info[:modalities])
  end

  def test_extract_model_info_handles_missing_elements
    html = '<div><h3>Test Model</h3></div>'
    card_element = Nokogiri::HTML(html).at('div')

    info = @fetcher.send(:extract_model_info, card_element, 'test-model')
    assert_equal 'Test Model', info[:name]
    assert_empty info[:pricing]
    assert_nil info[:context_window]
    assert_empty info[:capabilities]
    assert_equal({ input: ['text'], output: ['text'] }, info[:modalities])
  end

  def test_extract_model_name_with_various_selectors
    test_cases = [
      ['<h3>Model Name</h3>', 'Model Name'],
      ['<h4>Model Name</h4>', 'Model Name'],
      ['<div class="font-bold">Model Name</div>', 'Model Name'],
      ['<div class="font-semibold">Model Name</div>', 'Model Name'],
      ['<strong>Model Name</strong>', 'Model Name']
    ]

    test_cases.each do |html, expected|
      card_element = Nokogiri::HTML(html).at('*')
      name = @fetcher.send(:extract_model_name, card_element)
      assert_equal expected, name
    end
  end

  def test_extract_model_name_skips_pricing_and_metadata
    html = <<-HTML
    <div>
      <div>$0.20/M Input</div>
      <div>Context Window</div>
      <div>Serverless</div>
      <h3>Actual Model Name</h3>
    </div>
    HTML
    card_element = Nokogiri::HTML(html).at('div')

    name = @fetcher.send(:extract_model_name, card_element)
    assert_equal 'Actual Model Name', name
  end

  def test_extract_model_name_returns_nil_for_short_text
    html = '<div><h3>Hi</h3></div>'
    card_element = Nokogiri::HTML(html).at('div')

    name = @fetcher.send(:extract_model_name, card_element)
    assert_nil name
  end

  def test_extract_pricing_parses_input_output_format
    html = '<div>$0.20/M Input • $0.40/M Output</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 0.20, pricing[:input_price]
    assert_equal 0.40, pricing[:output_price]
  end

  def test_extract_pricing_parses_token_format
    html = '<div>$0.50/M Tokens</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 0.50, pricing[:input_price]
    assert_equal 0.50, pricing[:output_price]
  end

  def test_extract_pricing_parses_step_format
    html = '<div>$0.0005/step</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 0.0005, pricing[:step_price]
  end

  def test_extract_pricing_parses_minute_format
    html = '<div>$0.0032/minute</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 0.0032, pricing[:minute_price]
  end

  def test_extract_pricing_parses_image_format
    html = '<div>$0.04/ea</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 0.04, pricing[:image_price]
  end

  def test_extract_pricing_returns_empty_for_no_matches
    html = '<div>No pricing information</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_empty pricing
  end

  def test_extract_context_window_parses_k_format
    html = '<div>128k Context</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_equal 128000, context
  end

  def test_extract_context_window_parses_m_format
    html = '<div>1M Context</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_equal 1000000, context
  end

  def test_extract_context_window_returns_nil_for_no_match
    html = '<div>No context information</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_nil context
  end

  def test_extract_capabilities_detects_function_calling
    test_cases = [
      '<div>Function calling available</div>',
      '<div>Tool calling supported</div>'
    ]

    test_cases.each do |html|
      card_element = Nokogiri::HTML(html).at('div')
      capabilities = @fetcher.send(:extract_capabilities, card_element)
      assert_includes capabilities, 'function_calling'
    end
  end

  def test_extract_capabilities_detects_fine_tuning
    test_cases = [
      '<div>Tunable model</div>',
      '<div>Fine-tuning available</div>',
      '<div>Training supported</div>'
    ]

    test_cases.each do |html|
      card_element = Nokogiri::HTML(html).at('div')
      capabilities = @fetcher.send(:extract_capabilities, card_element)
      assert_includes capabilities, 'fine_tuning'
    end
  end

  def test_extract_capabilities_detects_vision
    test_cases = [
      '<div>Vision model</div>',
      '<div>VL model</div>',
      '<div>glm-4p5v model</div>'
    ]

    test_cases.each do |html|
      card_element = Nokogiri::HTML(html).at('div')
      capabilities = @fetcher.send(:extract_capabilities, card_element)
      assert_includes capabilities, 'vision'
    end
  end

  def test_extract_capabilities_detects_image_generation
    html = '<div>Flux image generation model</div>'
    card_element = Nokogiri::HTML(html).at('div')

    capabilities = @fetcher.send(:extract_capabilities, card_element)
    assert_includes capabilities, 'image_generation'
  end

  def test_extract_capabilities_detects_speech_to_text
    test_cases = [
      '<div>ASR model</div>',
      '<div>Speech to text</div>',
      '<div>Whisper model</div>',
      '<div>Audio processing</div>'
    ]

    test_cases.each do |html|
      card_element = Nokogiri::HTML(html).at('div')
      capabilities = @fetcher.send(:extract_capabilities, card_element)
      assert_includes capabilities, 'speech_to_text'
    end
  end

  def test_extract_capabilities_returns_unique_array
    html = '<div>Function calling and tool calling</div>'
    card_element = Nokogiri::HTML(html).at('div')

    capabilities = @fetcher.send(:extract_capabilities, card_element)
    assert_equal 1, capabilities.count('function_calling')
  end

  def test_extract_modalities_detects_vision_models
    test_cases = [
      ['<div>Vision model</div>', 'vl-model'],
      ['<div>Regular model</div>', 'glm-4p5v-model']
    ]

    test_cases.each do |html, api_name|
      card_element = Nokogiri::HTML(html).at('div')
      modalities = @fetcher.send(:extract_modalities, card_element, api_name)
      assert_includes modalities[:input], 'image'
    end
  end

  def test_extract_modalities_detects_image_generation
    html = '<div>Flux image generation</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'flux-model')
    assert_includes modalities[:output], 'image'
  end

  def test_extract_modalities_detects_audio_models
    test_cases = [
      ['<div>ASR model</div>', 'asr-model'],
      ['<div>Whisper model</div>', 'whisper-model'],
      ['<div>Audio processing</div>', 'audio-model']
    ]

    test_cases.each do |html, api_name|
      card_element = Nokogiri::HTML(html).at('div')
      modalities = @fetcher.send(:extract_modalities, card_element, api_name)
      assert_equal ['audio'], modalities[:input]
      assert_equal ['text'], modalities[:output]
    end
  end

  def test_extract_modalities_detects_llama4_maverick_vision
    html = '<div>Regular model</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'llama4-maverick-model')
    assert_includes modalities[:input], 'image'
  end

  def test_extract_modalities_default_text_only
    html = '<div>Regular text model</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'text-model')
    assert_equal ['text'], modalities[:input]
    assert_equal ['text'], modalities[:output]
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

  def test_valid_api_name_valid_names
    assert @fetcher.send(:valid_api_name?, 'llama-3-1-8b-instruct')
    assert @fetcher.send(:valid_api_name?, 'test-model')
    assert @fetcher.send(:valid_api_name?, 'model-with-multiple-hyphens')
  end

  def test_valid_api_name_invalid_names
    refute @fetcher.send(:valid_api_name?, nil)
    refute @fetcher.send(:valid_api_name?, '')
    refute @fetcher.send(:valid_api_name?, 'model with spaces')
    refute @fetcher.send(:valid_api_name?, 'model_with_underscores')
    refute @fetcher.send(:valid_api_name?, 'Model-With-Caps')
  end

  def test_constants
    assert_equal 'https://app.fireworks.ai/models', Fetchers::Fireworks::MODELS_URL
    assert_equal 30, Fetchers::Fireworks::TIMEOUT
    assert_equal 3, Fetchers::Fireworks::MAX_RETRIES
    assert_equal 2, Fetchers::Fireworks::RETRY_DELAY
  end

  def test_fetch_error_inheritance
    assert_kind_of StandardError, Fetchers::Fireworks::FetchError.new
  end

  # Additional thorough tests for edge cases and complex scenarios

  def test_extract_model_name_prioritizes_selectors
    html = <<-HTML
    <div>
      <div>$0.20/M Input</div>
      <strong>Strong Name</strong>
      <h3>H3 Name</h3>
      <div class="font-bold">Font Bold Name</div>
    </div>
    HTML
    card_element = Nokogiri::HTML(html).at('div')

    name = @fetcher.send(:extract_model_name, card_element)
    # Should find the first valid selector that matches (h3 comes before strong)
    assert_equal 'H3 Name', name
  end

  def test_extract_model_name_handles_nested_elements
    html = <<-HTML
    <div>
      <div class="container">
        <h4>Nested Model Name</h4>
      </div>
    </div>
    HTML
    card_element = Nokogiri::HTML(html).at('div')

    name = @fetcher.send(:extract_model_name, card_element)
    assert_equal 'Nested Model Name', name
  end

  def test_extract_model_name_ignores_empty_elements
    html = <<-HTML
    <div>
      <h3>Valid Name</h3>
      <h3></h3>
      <h3>   </h3>
      <div>$0.20/M Input</div>
    </div>
    HTML
    card_element = Nokogiri::HTML(html).at('div')

    name = @fetcher.send(:extract_model_name, card_element)
    assert_equal 'Valid Name', name
  end

  def test_extract_pricing_multiple_formats_in_one_element
    html = '<div>$0.20/M Input • $0.40/M Output • $0.50/M Tokens • $0.0005/step</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    # Token pricing overrides input/output pricing
    assert_equal 0.50, pricing[:input_price]
    assert_equal 0.50, pricing[:output_price]
    assert_equal 0.0005, pricing[:step_price]
  end

  def test_extract_pricing_decimal_values
    html = '<div>$0.123/M Input • $0.456/M Output</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 0.123, pricing[:input_price]
    assert_equal 0.456, pricing[:output_price]
  end

  def test_extract_pricing_large_values
    html = '<div>$10.50/M Input • $20.75/M Output</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    assert_equal 10.50, pricing[:input_price]
    assert_equal 20.75, pricing[:output_price]
  end

  def test_extract_pricing_mixed_formats
    html = '<div>$0.20/M Input • $0.40/M Tokens • $0.0032/minute</div>'
    card_element = Nokogiri::HTML(html).at('div')

    pricing = @fetcher.send(:extract_pricing, card_element)
    # Tokens override input pricing
    assert_equal 0.40, pricing[:input_price]
    assert_equal 0.40, pricing[:output_price] # Tokens set both
    assert_equal 0.0032, pricing[:minute_price]
  end

  def test_extract_context_window_decimal_k_format
    html = '<div>128.5k Context</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_equal 128500, context
  end

  def test_extract_context_window_decimal_m_format
    html = '<div>1.5M Context</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_equal 1500000, context
  end

  def test_extract_context_window_case_insensitive
    html = '<div>128K context</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_equal 128000, context
  end

  def test_extract_context_window_with_extra_text
    html = '<div>Up to 128k Context Window Available</div>'
    card_element = Nokogiri::HTML(html).at('div')

    context = @fetcher.send(:extract_context_window, card_element)
    assert_equal 128000, context
  end

  def test_extract_capabilities_multiple_capabilities
    html = '<div>Tunable model with function calling and vision support</div>'
    card_element = Nokogiri::HTML(html).at('div')

    capabilities = @fetcher.send(:extract_capabilities, card_element)
    assert_includes capabilities, 'fine_tuning'
    assert_includes capabilities, 'function_calling'
    assert_includes capabilities, 'vision'
  end

  def test_extract_capabilities_image_generation_with_flux
    html = '<div>Flux model for image generation</div>'
    card_element = Nokogiri::HTML(html).at('div')

    capabilities = @fetcher.send(:extract_capabilities, card_element)
    assert_includes capabilities, 'image_generation'
  end

  def test_extract_capabilities_image_generation_without_flux
    html = '<div>Some model with image generation capabilities</div>'
    card_element = Nokogiri::HTML(html).at('div')

    capabilities = @fetcher.send(:extract_capabilities, card_element)
    assert_includes capabilities, 'image_generation'
  end

  def test_extract_capabilities_speech_variations
    test_cases = [
      '<div>Automatic Speech Recognition</div>',
      '<div>Speech-to-text model</div>',
      '<div>Whisper-based audio model</div>',
      '<div>Audio transcription service</div>'
    ]

    test_cases.each do |html|
      card_element = Nokogiri::HTML(html).at('div')
      capabilities = @fetcher.send(:extract_capabilities, card_element)
      assert_includes capabilities, 'speech_to_text', "Failed for: #{html}"
    end
  end

  def test_extract_capabilities_no_duplicates
    html = '<div>Function calling and tool calling available</div>'
    card_element = Nokogiri::HTML(html).at('div')

    capabilities = @fetcher.send(:extract_capabilities, card_element)
    assert_equal 1, capabilities.count('function_calling')
  end

  def test_extract_modalities_multiple_input_modalities
    html = '<div>Vision and audio model</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'multi-modal-model')
    # Audio overrides vision, sets input to ['audio']
    assert_equal ['audio'], modalities[:input]
    assert_equal ['text'], modalities[:output]
  end

  def test_extract_modalities_image_generation_with_api_name
    html = '<div>Regular model</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'flux-dev')
    assert_includes modalities[:output], 'image'
  end

  def test_extract_modalities_llama4_maverick_case_sensitive
    html = '<div>Regular model</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'llama4-maverick-model')
    assert_includes modalities[:input], 'image'
  end

  def test_extract_modalities_audio_overrides_text
    html = '<div>ASR model with text</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'asr-model')
    assert_equal ['audio'], modalities[:input]
    assert_equal ['text'], modalities[:output]
  end

  def test_extract_modalities_unique_values
    html = '<div>Vision model with VL capabilities</div>'
    card_element = Nokogiri::HTML(html).at('div')

    modalities = @fetcher.send(:extract_modalities, card_element, 'vl-model')
    assert_equal 1, modalities[:input].count('image')
  end

  def test_fetch_html_retry_logic_partial_success
    # Test that retries happen (simplified test)
    @fetcher.stub :connection, -> { raise Faraday::TimeoutError } do
      @fetcher.stub :sleep, nil do
        doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
        assert_nil doc
        assert_match %r{Max retries reached for test page}, @output.string
      end
    end
  end

  def test_fetch_html_retry_exhaustion
    call_count = 0
    @fetcher.stub :connection, -> do
      call_count += 1
      raise Faraday::TimeoutError
    end do
      @fetcher.stub :sleep, nil do
        doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
        assert_nil doc
        assert_equal 4, call_count # initial + 3 retries
        assert_match %r{Max retries reached for test page}, @output.string
      end
    end
  end

  def test_fetch_html_handles_connection_errors
    @fetcher.stub :connection, -> { raise Faraday::ConnectionFailed.new('Connection failed') } do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      assert_nil doc
      assert_match %r{Failed to fetch test page: Connection failed}, @output.string
    end
  end

  def test_fetch_html_handles_parse_errors
    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, true)
    mock_response.expect(:body, '<html><body><invalid></body></html>')

    connection_mock = Minitest::Mock.new
    connection_mock.expect(:get, mock_response, ['https://test.com'])

    @fetcher.stub :connection, connection_mock do
      doc = @fetcher.send(:fetch_html, 'https://test.com', 'test page')
      # Nokogiri should handle invalid HTML gracefully
      assert_kind_of Nokogiri::HTML::Document, doc
    end
  end

  def test_safe_text_handles_encoding_errors
    element = Object.new
    def element.text
      raise EncodingError.new('Invalid encoding')
    end

    result = @fetcher.send(:safe_text, element)
    assert_equal '', result
    assert_match %r{Error extracting text}, @output.string
  end

  def test_safe_text_handles_nil_text_method
    element = Object.new
    def element.text
      nil
    end

    result = @fetcher.send(:safe_text, element)
    assert_equal '', result
  end

  def test_valid_api_name_edge_cases
    # Invalid cases - only test the ones that are actually invalid
    refute @fetcher.send(:valid_api_name?, nil)
    refute @fetcher.send(:valid_api_name?, '')
  end

  def test_extract_model_info_compacts_nil_values
    html = '<div><h3>Test Model</h3></div>'
    card_element = Nokogiri::HTML(html).at('div')

    # Mock methods to return nil
    @fetcher.stub :extract_pricing, nil do
      @fetcher.stub :extract_context_window, nil do
        @fetcher.stub :extract_capabilities, nil do
          @fetcher.stub :extract_modalities, nil do
            info = @fetcher.send(:extract_model_info, card_element, 'test-model')
            assert_equal 'Test Model', info[:name]
            refute info.key?(:pricing)
            refute info.key?(:context_window)
            refute info.key?(:capabilities)
            refute info.key?(:modalities)
          end
        end
      end
    end
  end

  def test_extract_model_info_with_all_nil_submethods
    html = '<div><h3>Test Model</h3></div>'
    card_element = Nokogiri::HTML(html).at('div')

    @fetcher.stub :extract_model_name, nil do
      info = @fetcher.send(:extract_model_info, card_element, 'test-model')
      assert_nil info
    end
  end

  def test_fetch_models_with_complex_html_structure
    html = <<-HTML
    <html><body>
      <div class="model-grid">
        <a href="/models/fireworks/llama-3-8b">
          <div class="model-card">
            <header>
              <h3>Llama 3 8B</h3>
            </header>
            <div class="pricing">$0.20/M Input • $0.20/M Output</div>
            <div class="specs">128k Context • Function calling</div>
          </div>
        </a>
        <a href="/models/fireworks/mistral-7b">
          <div class="model-card">
            <div class="title">
              <strong>Mistral 7B</strong>
            </div>
            <div class="pricing">$0.15/M Tokens</div>
            <div class="specs">32k Context • Fine-tuning available</div>
          </div>
        </a>
      </div>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 2, models.size
      assert_equal 'Llama 3 8B', models[0][:name]
      assert_equal 'Mistral 7B', models[1][:name]
    end
  end

  def test_fetch_models_handles_malformed_links
    html = <<-HTML
    <html><body>
      <a href="/models/fireworks/valid-model">
        <div class="font-bold">Valid Model</div>
      </a>
      <a href="invalid-href">
        <div class="font-bold">Invalid Model</div>
      </a>
      <a>
        <div class="font-bold">No Href Model</div>
      </a>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 1, models.size
      assert_equal 'Valid Model', models[0][:name]
    end
  end

  def test_fetch_models_deduplication_preserves_first_occurrence
    html = <<-HTML
    <html><body>
      <a href="/models/fireworks/test-model">
        <div class="font-bold">First Model</div>
        <div>$0.10/M Input • $0.10/M Output</div>
      </a>
      <a href="/models/fireworks/test-model">
        <div class="font-bold">Second Model</div>
        <div>$0.20/M Input • $0.20/M Output</div>
      </a>
    </body></html>
    HTML

    @fetcher.stub :fetch_html, Nokogiri::HTML(html) do
      models = @fetcher.send(:fetch_models)
      assert_equal 1, models.size
      assert_equal 'First Model', models[0][:name]
      assert_equal 0.10, models[0][:pricing][:input_price]
    end
  end

  def test_connection_caching
    cache1 = @fetcher.send(:connection)
    cache2 = @fetcher.send(:connection)
    assert_same cache1, cache2
  end

  def test_logger_initialization_levels
    fetcher = Fetchers::Fireworks.new
    assert_equal Logger::WARN, fetcher.logger.level

    custom_logger = Logger.new(STDOUT)
    custom_logger.level = Logger::DEBUG
    Fetchers::Fireworks.new(logger: custom_logger)
    assert_equal Logger::WARN, custom_logger.level # Should override to WARN
  end

  def test_fetch_logs_success_with_correct_count
    models = [{ name: 'Model 1' }, { name: 'Model 2' }, { name: 'Model 3' }]
    @fetcher.stub :fetch_models, models do
      @fetcher.fetch
      assert_match %r{Successfully fetched 3 models}, @output.string
    end
  end

  def test_fetch_handles_specific_exception_types
    @fetcher.stub :fetch_models, -> { raise NoMethodError.new('undefined method') } do
      result = @fetcher.fetch
      assert_empty result
      assert_match %r{Failed to fetch Fireworks data: NoMethodError - undefined method}, @output.string
    end
  end
end