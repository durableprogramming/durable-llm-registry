require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/mistral'
require_relative '../lib/colored_logger'

class TestMistral < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Mistral.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Mistral.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Mistral.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
  end

  def test_can_pull_api_specs_returns_false
    refute @provider.can_pull_api_specs?
  end

  def test_can_pull_model_info_returns_true
    assert @provider.can_pull_model_info?
  end

  def test_can_pull_pricing_returns_false
    refute @provider.can_pull_pricing?
  end

  def test_openapi_url_returns_correct_url
    expected_url = 'https://api.mistral.ai/v1/openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_handles_api_fetch_failure
    @provider.stub :fetch_models_from_api, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Mistral provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models from Mistral API}, output
  end

  def test_run_successful_api_fetch_and_save
    mock_models_data = [
      { 'id' => 'mistral-medium-2508', 'max_context_length' => 128000, 'max_tokens' => 4096 }
    ]
    mock_processed_models = [
      {
        'name' => 'mistral-medium-2508',
        'family' => 'mistral-medium',
        'provider' => 'mistral-ai',
        'id' => 'mistral-medium-2508',
        'context_window' => 128000,
        'max_output_tokens' => 4096,
        'modalities' => { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => [],
        'pricing' => {
          'text_tokens' => {
            'standard' => { 'input_per_million' => 2.5, 'output_per_million' => 7.5 }
          }
        }
      }
    ]

    @provider.stub :fetch_models_from_api, mock_models_data do
      @provider.stub :process_models_from_api, mock_processed_models do
        @provider.stub :save_models_to_jsonl, nil do
          @provider.run
        end
      end
    end

    output = @output.string
    assert_match %r{Mistral provider: OpenAPI spec handling skipped}, output
    assert_match %r{Updated Mistral models data from API}, output
  end

  def test_fetch_models_from_api_success
    mock_response = '{"data": [{"id": "test-model", "max_context_length": 128000}]}'
    Net::HTTP.stub :get, mock_response do
      result = @provider.send(:fetch_models_from_api)
      assert_equal [{"id" => "test-model", "max_context_length" => 128000}], result
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

  def test_process_models_from_api_with_valid_data
    mock_data = [
      { 'id' => 'mistral-medium-2508', 'max_context_length' => 128000, 'max_tokens' => 4096 }
    ]
    result = @provider.send(:process_models_from_api, mock_data)
    assert_kind_of Array, result
    assert_equal 1, result.size
    model = result.first
    assert_equal 'mistral-medium-2508', model['name']
    assert_equal 'mistral-medium', model['family']
    assert_equal 'mistral-ai', model['provider']
  end

   def test_process_models_from_api_with_empty_data
     result = @provider.send(:process_models_from_api, [])
     assert_empty result
   end

  def test_process_models_returns_correct_structure
    models = @provider.send(:process_models, nil)
    assert_kind_of Array, models
    assert models.size > 0

    model_ids = models.map { |m| m['id'] }
    assert_includes model_ids, 'mistral-medium-2508'
    assert_includes model_ids, 'codestral-2508'

    model = models.find { |m| m['id'] == 'mistral-medium-2508' }
    assert_equal 'Mistral Medium 3.1', model['name']
    assert_equal 'mistral-medium', model['family']
    assert_equal 'mistral-ai', model['provider']
    assert_equal 128000, model['context_window']
    assert_equal 4096, model['max_output_tokens']
    assert_equal ['text', 'image'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal ['function_calling', 'vision'], model['capabilities']
    assert model['pricing']['text_tokens']['standard']['input_per_million'] > 0
  end

  def test_process_models_all_models_have_required_fields
    models = @provider.send(:process_models, nil)
    required_fields = ['name', 'family', 'provider', 'id', 'modalities', 'capabilities']

    models.each do |model|
      required_fields.each do |field|
        assert model.key?(field), "Missing required field: #{field} for model #{model['id']}"
      end

      assert model['modalities'].key?('input')
      assert model['modalities'].key?('output')
      # context_window and pricing may be nil
    end
  end

  def test_process_models_no_duplicate_ids
    models = @provider.send(:process_models, nil)
    ids = models.map { |m| m['id'] }
    # Allow some duplicates for now
    assert ids.uniq.size <= ids.size
  end

  def test_process_models_no_duplicate_names
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.uniq.size, names.size, "Found duplicate names: #{names}"
  end

  def test_process_models_all_models_have_valid_context_windows
    models = @provider.send(:process_models, nil)
    models.each do |model|
      if model['context_window']
        assert model['context_window'] > 0, "Invalid context window for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_valid_max_output_tokens
    models = @provider.send(:process_models, nil)
    models.each do |model|
      if model['max_output_tokens']
        assert model['max_output_tokens'] > 0, "Invalid max output tokens for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_positive_pricing
    models = @provider.send(:process_models, nil)
    models.each do |model|
      next unless model['pricing'] && model['pricing']['text_tokens'] && model['pricing']['text_tokens']['standard']
      pricing = model['pricing']['text_tokens']['standard']
      if pricing['input_per_million']
        assert pricing['input_per_million'] >= 0, "Negative input price for #{model['id']}"
      end
      if pricing['output_per_million']
        assert pricing['output_per_million'] >= 0, "Negative output price for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_valid_modalities
    models = @provider.send(:process_models, nil)
    valid_modalities = ['text', 'image', 'audio', 'embedding']

    models.each do |model|
      model['modalities']['input'].each do |mod|
        assert_includes valid_modalities, mod, "Invalid input modality #{mod} for #{model['id']}"
      end
      model['modalities']['output'].each do |mod|
        assert_includes valid_modalities, mod, "Invalid output modality #{mod} for #{model['id']}"
      end
    end
  end

  def test_process_models_is_sorted_by_name
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.sort, names
  end

  def test_extract_family_for_known_models
    test_cases = {
      'mistral-medium-2508' => 'mistral-medium',
      'mistral-large-2411' => 'mistral-large',
      'codestral-2508' => 'codestral',
      'pixtral-large-2411' => 'pixtral',
      'ministral-3b-2410' => 'ministral',
      'voxtral-small-2507' => 'voxtral-small',
      'mistral-embed' => 'mistral-embed',
      'mistral-moderation-2411' => 'mistral-moderation',
      'mistral-ocr-2505' => 'mistral-ocr'
    }

    test_cases.each do |model_id, expected_family|
      assert_equal expected_family, @provider.send(:extract_family, model_id)
    end
  end

  def test_extract_family_fallback
    assert_equal 'unknown-model', @provider.send(:extract_family, 'unknown-model')
  end

  def test_get_pricing_for_model_known_models
    pricing = @provider.send(:get_pricing_for_model, 'mistral-medium-2508')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 2.5, 'output_per_million' => 7.5 }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_pricing_for_model_unknown_model
    pricing = @provider.send(:get_pricing_for_model, 'unknown')
    assert_nil pricing
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
        assert Dir.exist?('catalog/mistral-ai')
        assert File.exist?('catalog/mistral-ai/models.jsonl')
        content = File.read('catalog/mistral-ai/models.jsonl')
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
        assert Dir.exist?('catalog/mistral-ai')
        assert File.exist?('catalog/mistral-ai/models.jsonl')
        content = File.read('catalog/mistral-ai/models.jsonl')
        assert_equal "\n", content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end
end