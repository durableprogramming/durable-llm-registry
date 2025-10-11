require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/openrouter'
require_relative '../lib/colored_logger'

class TestOpenRouter < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::OpenRouter.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::OpenRouter.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::OpenRouter.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
  end

  def test_can_pull_api_specs_returns_false
    refute @provider.can_pull_api_specs?
  end

  def test_can_pull_model_info_returns_true
    assert @provider.can_pull_model_info?
  end

  def test_can_pull_pricing_returns_true
    assert @provider.can_pull_pricing?
  end

  def test_openapi_url_returns_correct_url
    expected_url = 'https://openrouter.ai/api/v1/openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_handles_api_fetch_failure
    @provider.stub :fetch_models_from_api, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{OpenRouter provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models from API}, output
  end

  def test_run_successful_api_fetch_and_save
    mock_api_data = {
      'data' => [
        {
          'id' => 'anthropic/claude-3.5-sonnet',
          'name' => 'Claude 3.5 Sonnet',
          'context_length' => 200000,
          'top_provider' => { 'max_completion_tokens' => 4096 },
          'architecture' => {
            'input_modalities' => ['text'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.003, 'completion' => 0.015 }
        }
      ]
    }
    mock_processed_models = [
      {
        'name' => 'Claude 3.5 Sonnet',
        'family' => 'anthropic',
        'provider' => 'openrouter',
        'id' => 'anthropic/claude-3.5-sonnet',
        'context_window' => 200000,
        'max_output_tokens' => 4096,
        'modalities' => { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => [],
        'pricing' => {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => 3000.0,
              'output_per_million' => 15000.0
            }
          }
        }
      }
    ]

    @provider.stub :fetch_models_from_api, mock_api_data do
      Providers::OpenRouter.stub :process_models, mock_processed_models do
        @provider.stub :save_models_to_jsonl, nil do
          @provider.run
        end
      end
    end

    output = @output.string
    assert_match %r{OpenRouter provider: OpenAPI spec handling skipped}, output
    assert_match %r{Updated OpenRouter models data from API}, output
  end

  def test_fetch_models_from_api_success
    mock_response = '{"data": [{"id": "test-model", "name": "Test Model"}]}'
    Net::HTTP.stub :get, mock_response do
      result = @provider.send(:fetch_models_from_api)
      assert_equal({"data" => [{"id" => "test-model", "name" => "Test Model"}]}, result)
    end
  end

  def test_fetch_models_from_api_json_parse_error
    Net::HTTP.stub :get, 'invalid json' do
      result = @provider.send(:fetch_models_from_api)
      assert_nil result
    end
  end

  def test_fetch_models_from_api_network_error
    Net::HTTP.stub :get, -> { raise StandardError.new('Network error') } do
      result = @provider.send(:fetch_models_from_api)
      assert_nil result
    end
  end

  def test_process_models_with_valid_data
    mock_data = {
      'data' => [
        {
          'id' => 'anthropic/claude-3.5-sonnet',
          'name' => 'Claude 3.5 Sonnet',
          'context_length' => 200000,
          'top_provider' => { 'max_completion_tokens' => 4096 },
          'architecture' => {
            'input_modalities' => ['text'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.003, 'completion' => 0.015 }
        }
      ]
    }
    result = Providers::OpenRouter.process_models(mock_data)
    assert_kind_of Array, result
    assert_equal 1, result.size
    model = result.first
    assert_equal 'Claude 3.5 Sonnet', model['name']
    assert_equal 'anthropic', model['family']
    assert_equal 'openrouter', model['provider']
    assert_equal 'anthropic/claude-3.5-sonnet', model['id']
    assert_equal 200000, model['context_window']
    assert_equal 4096, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal [], model['capabilities']
    assert_equal 3000.0, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 15000.0, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_with_missing_max_completion_tokens
    mock_data = {
      'data' => [
        {
          'id' => 'test/model',
          'name' => 'Test Model',
          'context_length' => 100000,
          'architecture' => {
            'input_modalities' => ['text'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.001, 'completion' => 0.002 }
        }
      ]
    }
    result = Providers::OpenRouter.process_models(mock_data)
    model = result.first
    assert_nil model['max_output_tokens']
  end

  def test_process_models_with_image_modalities
    mock_data = {
      'data' => [
        {
          'id' => 'test/model',
          'name' => 'Test Model',
          'context_length' => 100000,
          'architecture' => {
            'input_modalities' => ['text', 'image'],
            'output_modalities' => ['text', 'image']
          },
          'pricing' => { 'prompt' => 0.001, 'completion' => 0.002 }
        }
      ]
    }
    result = Providers::OpenRouter.process_models(mock_data)
    model = result.first
    assert_equal ['text', 'image'], model['modalities']['input']
    assert_equal ['text', 'image'], model['modalities']['output']
  end

  def test_process_models_with_audio_modalities
    mock_data = {
      'data' => [
        {
          'id' => 'test/model',
          'name' => 'Test Model',
          'context_length' => 100000,
          'architecture' => {
            'input_modalities' => ['audio'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.001, 'completion' => 0.002 }
        }
      ]
    }
    result = Providers::OpenRouter.process_models(mock_data)
    model = result.first
    assert_equal ['audio'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
  end

  def test_process_models_pricing_conversion
    mock_data = {
      'data' => [
        {
          'id' => 'test/model',
          'name' => 'Test Model',
          'context_length' => 100000,
          'architecture' => {
            'input_modalities' => ['text'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.0005, 'completion' => 0.002 }
        }
      ]
    }
    result = Providers::OpenRouter.process_models(mock_data)
    model = result.first
    assert_equal 500.0, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 2000.0, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_is_sorted_by_name
    mock_data = {
      'data' => [
        {
          'id' => 'z/model',
          'name' => 'Z Model',
          'context_length' => 100000,
          'architecture' => {
            'input_modalities' => ['text'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.001, 'completion' => 0.002 }
        },
        {
          'id' => 'a/model',
          'name' => 'A Model',
          'context_length' => 100000,
          'architecture' => {
            'input_modalities' => ['text'],
            'output_modalities' => ['text']
          },
          'pricing' => { 'prompt' => 0.001, 'completion' => 0.002 }
        }
      ]
    }
    result = Providers::OpenRouter.process_models(mock_data)
    names = result.map { |m| m['name'] }
    assert_equal ['A Model', 'Z Model'], names
  end

  def test_save_models_to_jsonl_creates_directory_and_file
    models = [
      { 'id' => 'test-model-1', 'name' => 'Test Model 1' },
      { 'id' => 'test-model-2', 'name' => 'Test Model 2' }
    ]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/openrouter')
        assert File.exist?('catalog/openrouter/models.jsonl')
        content = File.read('catalog/openrouter/models.jsonl')
        lines = content.strip.split("\n")
        assert_equal 2, lines.size
        parsed = lines.map { |line| JSON.parse(line) }
        assert_equal models, parsed
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_models_to_jsonl_with_empty_array
    models = []

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/openrouter')
        assert File.exist?('catalog/openrouter/models.jsonl')
        content = File.read('catalog/openrouter/models.jsonl')
        assert_equal "\n", content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end
end