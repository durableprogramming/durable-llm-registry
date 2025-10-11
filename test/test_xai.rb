require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/xai'
require_relative '../lib/colored_logger'

class TestXAI < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::XAI.new(logger: @logger)
  end

  def test_can_pull_api_specs_returns_true
    assert @provider.can_pull_api_specs?
  end

  def test_can_pull_model_info_returns_false
    refute @provider.can_pull_model_info?
  end

  def test_can_pull_pricing_returns_false
    refute @provider.can_pull_pricing?
  end

  def test_openapi_url_returns_correct_url
    assert_equal 'https://api.x.ai/api-docs/openapi.json', @provider.openapi_url
  end

  def test_run_downloads_and_saves_spec
    mock_spec_content = '{"openapi": "3.0.0", "info": {"title": "Test API"}}'
    expected_yaml = YAML.dump(JSON.parse(mock_spec_content))

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Updated XAI openapi spec}, output
    assert_match %r{XAI models data update skipped}, output
  end

  def test_run_converts_json_to_yaml_when_url_ends_with_json
    mock_spec_content = '{"openapi": "3.0.0", "info": {"title": "Test API"}}'
    expected_yaml = YAML.dump(JSON.parse(mock_spec_content))

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.run
      end
    end

    # Verify that save_spec_to_catalog was called with YAML content
    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, ->(provider, content) {
        assert_equal 'xai', provider
        assert_equal expected_yaml, content
      } do
        @provider.run
      end
    end
  end

  def test_run_handles_yaml_url_without_conversion
    mock_spec_content = "openapi: 3.0.0\ninfo:\n  title: Test API\n"

    @provider.stub :openapi_url, 'https://api.x.ai/api-docs/openapi.yaml' do
      @provider.stub :download_openapi_spec, mock_spec_content do
        @provider.stub :save_spec_to_catalog, ->(provider, content) {
          assert_equal 'xai', provider
          assert_equal mock_spec_content, content
        } do
          @provider.run
        end
      end
    end
  end

  def test_fetch_models_data_returns_expected_structure
    data = @provider.send(:fetch_models_data)
    assert_kind_of Hash, data
    assert data.key?('data')
    assert_kind_of Array, data['data']
    assert_equal 6, data['data'].size

    expected_ids = ['grok-4-0709', 'grok-code-fast-1', 'grok-3', 'grok-3-mini', 'grok-2-vision-1212', 'grok-2-image-1212']
    actual_ids = data['data'].map { |m| m['id'] }
    assert_equal expected_ids, actual_ids

    data['data'].each do |model|
      assert model.key?('id')
      assert model.key?('context_length')
      assert model.key?('max_tokens')
      assert_equal 128000, model['context_length']
      assert_equal 32768, model['max_tokens']
    end
  end

  def test_save_models_to_jsonl_creates_directory_and_file
    models = [
      {'id' => 'test-model-1', 'context_length' => 1000, 'max_tokens' => 500},
      {'id' => 'test-model-2', 'context_length' => 2000, 'max_tokens' => 1000}
    ]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/xai')
        assert File.exist?('catalog/xai/models.jsonl')
        content = File.read('catalog/xai/models.jsonl')
        lines = content.strip.split("\n")
        assert_equal 2, lines.size
        parsed = lines.map { |line| JSON.parse(line) }
        assert_equal models, parsed
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_process_models_processes_all_models
    input_data = {
      'data' => [
        {'id' => 'grok-4-0709', 'context_length' => 128000, 'max_tokens' => 32768},
        {'id' => 'grok-3-mini', 'context_length' => 128000, 'max_tokens' => 32768}
      ]
    }

    result = Providers::XAI.process_models(input_data)

    assert_kind_of Array, result
    assert_equal 2, result.size

    # Check first model
    model1 = result.find { |m| m['id'] == 'grok-4-0709' }
    assert_equal 'Grok 4', model1['name']
    assert_equal 'grok-4', model1['family']
    assert_equal 'xai', model1['provider']
    assert_equal 128000, model1['context_window']
    assert_equal 32768, model1['max_output_tokens']
    assert_equal ['text'], model1['modalities']['input']
    assert_equal ['text'], model1['modalities']['output']
    assert_equal ['function_calling', 'reasoning'], model1['capabilities']
    assert model1['pricing'].key?('text_tokens')

    # Check second model
    model2 = result.find { |m| m['id'] == 'grok-3-mini' }
    assert_equal 'Grok 3 Mini', model2['name']
    assert_equal 'grok-3-mini', model2['family']
  end

  def test_process_models_sorts_by_name
    input_data = {
      'data' => [
        {'id' => 'grok-3', 'context_length' => 128000, 'max_tokens' => 32768},
        {'id' => 'grok-4-0709', 'context_length' => 128000, 'max_tokens' => 32768}
      ]
    }

    result = Providers::XAI.process_models(input_data)
    assert_equal 'Grok 3', result[0]['name']
    assert_equal 'Grok 4', result[1]['name']
  end

  def test_process_models_handles_missing_context_length
    input_data = {
      'data' => [
        {'id' => 'test-model', 'max_tokens' => 1000}
      ]
    }

    result = Providers::XAI.process_models(input_data)
    assert_equal 128000, result[0]['context_window']
  end

  def test_process_models_handles_missing_max_tokens
    input_data = {
      'data' => [
        {'id' => 'test-model', 'context_length' => 50000}
      ]
    }

    result = Providers::XAI.process_models(input_data)
    assert_equal 32768, result[0]['max_output_tokens']
  end

  def test_extract_family_grok_4
    assert_equal 'grok-4', Providers::XAI.extract_family('grok-4-0709')
    assert_equal 'grok-4', Providers::XAI.extract_family('grok-4-beta')
  end

  def test_extract_family_grok_code_fast
    assert_equal 'grok-code-fast', Providers::XAI.extract_family('grok-code-fast-1')
    assert_equal 'grok-code-fast', Providers::XAI.extract_family('grok-code-fast-v2')
  end

  def test_extract_family_grok_3_mini
    assert_equal 'grok-3-mini', Providers::XAI.extract_family('grok-3-mini')
    assert_equal 'grok-3-mini', Providers::XAI.extract_family('grok-3-mini-fast')
  end

  def test_extract_family_grok_3
    assert_equal 'grok-3', Providers::XAI.extract_family('grok-3')
    assert_equal 'grok-3', Providers::XAI.extract_family('grok-3-enhanced')
  end

  def test_extract_family_grok_2_vision
    assert_equal 'grok-2-vision', Providers::XAI.extract_family('grok-2-vision-1212')
    assert_equal 'grok-2-vision', Providers::XAI.extract_family('grok-2-vision-latest')
  end

  def test_extract_family_grok_2_image
    assert_equal 'grok-2-image', Providers::XAI.extract_family('grok-2-image-1212')
    assert_equal 'grok-2-image', Providers::XAI.extract_family('grok-2-image-new')
  end

  def test_extract_family_unknown_falls_back_to_grok
    assert_equal 'grok', Providers::XAI.extract_family('grok-5-experimental')
    assert_equal 'grok', Providers::XAI.extract_family('grok-beta')
    assert_equal 'grok', Providers::XAI.extract_family('unknown-model')
  end

  def test_get_display_name_known_models
    assert_equal 'Grok 4', Providers::XAI.get_display_name('grok-4-0709')
    assert_equal 'Grok Code Fast', Providers::XAI.get_display_name('grok-code-fast-1')
    assert_equal 'Grok 3', Providers::XAI.get_display_name('grok-3')
    assert_equal 'Grok 3 Mini', Providers::XAI.get_display_name('grok-3-mini')
    assert_equal 'Grok 2 Vision', Providers::XAI.get_display_name('grok-2-vision-1212')
    assert_equal 'Grok 2 Image', Providers::XAI.get_display_name('grok-2-image-1212')
  end

  def test_get_display_name_unknown_model_returns_id
    assert_equal 'unknown-model-123', Providers::XAI.get_display_name('unknown-model-123')
    assert_equal 'grok-5-new', Providers::XAI.get_display_name('grok-5-new')
  end

  def test_get_modalities_vision_model
    modalities = Providers::XAI.get_modalities('grok-2-vision-1212')
    assert_equal ['text', 'image'], modalities['input']
    assert_equal ['text'], modalities['output']
  end

  def test_get_modalities_image_model
    modalities = Providers::XAI.get_modalities('grok-2-image-1212')
    assert_equal ['text'], modalities['input']
    assert_equal ['image'], modalities['output']
  end

  def test_get_modalities_text_only_model
    modalities = Providers::XAI.get_modalities('grok-4-0709')
    assert_equal ['text'], modalities['input']
    assert_equal ['text'], modalities['output']
  end

  def test_get_modalities_unknown_model_defaults_to_text
    modalities = Providers::XAI.get_modalities('unknown-model')
    assert_equal ['text'], modalities['input']
    assert_equal ['text'], modalities['output']
  end

  def test_get_capabilities_returns_expected_array
    capabilities = Providers::XAI.get_capabilities('any-model-id')
    assert_equal ['function_calling', 'reasoning'], capabilities
  end

  def test_get_pricing_for_model_known_models
    pricing = Providers::XAI.get_pricing_for_model('grok-4-0709')
    assert_equal 5.0, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 15.0, pricing['text_tokens']['standard']['output_per_million']

    pricing = Providers::XAI.get_pricing_for_model('grok-3-mini')
    assert_equal 1.5, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 4.5, pricing['text_tokens']['standard']['output_per_million']

    pricing = Providers::XAI.get_pricing_for_model('grok-code-fast-1')
    assert_equal 3.0, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 9.0, pricing['text_tokens']['standard']['output_per_million']
  end

  def test_get_pricing_for_model_unknown_model_uses_default
    pricing = Providers::XAI.get_pricing_for_model('unknown-model')
    assert_equal 5.0, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 15.0, pricing['text_tokens']['standard']['output_per_million']
  end

  def test_get_pricing_for_model_all_models_have_pricing_structure
    known_models = ['grok-4-0709', 'grok-code-fast-1', 'grok-3', 'grok-3-mini', 'grok-2-vision-1212', 'grok-2-image-1212']

    known_models.each do |model_id|
      pricing = Providers::XAI.get_pricing_for_model(model_id)
      assert pricing.key?('text_tokens')
      assert pricing['text_tokens'].key?('standard')
      assert pricing['text_tokens']['standard'].key?('input_per_million')
      assert pricing['text_tokens']['standard'].key?('output_per_million')
    end
  end

  def test_run_logs_correct_messages
    @provider.stub :download_openapi_spec, '{}' do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Updated XAI openapi spec}, output
    assert_match %r{XAI models data update skipped}, output
  end

  def test_run_handles_json_parsing_errors
    invalid_json = '{"invalid": json}'
    @provider.stub :download_openapi_spec, invalid_json do
      assert_raises JSON::ParserError do
        @provider.run
      end
    end
  end

  def test_process_models_with_empty_data
    input_data = { 'data' => [] }
    result = Providers::XAI.process_models(input_data)
    assert_empty result
  end

  def test_process_models_with_nil_data
    input_data = { 'data' => nil }
    assert_raises NoMethodError do
      Providers::XAI.process_models(input_data)
    end
  end

  def test_extract_family_edge_cases
    assert_equal 'grok', Providers::XAI.extract_family('')
    assert_equal 'grok', Providers::XAI.extract_family('grok')
    assert_equal 'grok', Providers::XAI.extract_family('grok-')
  end

  def test_get_display_name_edge_cases
    assert_equal '', Providers::XAI.get_display_name('')
    assert_equal 'grok', Providers::XAI.get_display_name('grok')
  end

  def test_get_modalities_edge_cases
    modalities = Providers::XAI.get_modalities('')
    assert_equal ['text'], modalities['input']
    assert_equal ['text'], modalities['output']

    modalities = Providers::XAI.get_modalities('vision')
    assert_equal ['text', 'image'], modalities['input']
    assert_equal ['text'], modalities['output']

    modalities = Providers::XAI.get_modalities('image')
    assert_equal ['text'], modalities['input']
    assert_equal ['image'], modalities['output']
  end

  def test_get_pricing_for_model_edge_cases
    pricing = Providers::XAI.get_pricing_for_model('')
    assert pricing.key?('text_tokens')

    pricing = Providers::XAI.get_pricing_for_model(nil)
    assert pricing.key?('text_tokens')
  end

  def test_initialization_with_default_logger
    provider = Providers::XAI.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::XAI.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
  end
end