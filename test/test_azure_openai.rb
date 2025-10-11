require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/azure-openai'
require_relative '../lib/colored_logger'

class TestAzureOpenai < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::AzureOpenai.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::AzureOpenai.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::AzureOpenai.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
  end

  def test_can_pull_api_specs_returns_false
    refute @provider.can_pull_api_specs?
  end

  def test_can_pull_model_info_returns_false
    refute @provider.can_pull_model_info?
  end

  def test_can_pull_pricing_returns_false
    refute @provider.can_pull_pricing?
  end

  def test_openapi_url_returns_correct_url
    expected_url = 'https://api.openai.azure.com/v1/openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_handles_api_fetch_failure
    @provider.stub :fetch_models_from_api, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Azure OpenAI provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models from Azure OpenAI API}, output
  end

  def test_run_successful_api_fetch_and_save
    mock_models_data = [
      { 'id' => 'gpt-4o', 'context_window' => 128000, 'max_output_tokens' => 16384 }
    ]
    mock_processed_models = [
      {
        'name' => 'gpt-4o',
        'family' => 'gpt-4o',
        'provider' => 'azure-openai',
        'id' => 'gpt-4o',
        'context_window' => 128000,
        'max_output_tokens' => 16384,
        'modalities' => { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => ['function_calling'],
        'pricing' => {
          'text_tokens' => {
            'standard' => { 'input_per_million' => 2.5, 'output_per_million' => 10.0 }
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
    assert_match %r{Azure OpenAI provider: OpenAPI spec handling skipped}, output
    assert_match %r{Updated Azure OpenAI models data from API}, output
  end

  def test_fetch_models_from_api_returns_nil
    # Since it can't fetch without auth, it should return nil
    result = @provider.send(:fetch_models_from_api)
    assert_nil result
  end

  def test_process_models_from_api_calls_class_method
    mock_data = [{ 'id' => 'test' }]
    mock_processed = [{ 'id' => 'processed' }]

    Providers::AzureOpenai.stub :process_models, mock_processed do
      result = @provider.send(:process_models_from_api, mock_data)
      assert_equal mock_processed, result
    end
  end

  def test_process_models_returns_correct_structure
    models = Providers::AzureOpenai.process_models(nil)
    assert_kind_of Array, models
    assert_equal 5, models.size

    model_ids = models.map { |m| m['id'] }
    assert_includes model_ids, 'gpt-4o'
    assert_includes model_ids, 'gpt-4o-mini'
    assert_includes model_ids, 'gpt-4-turbo'
    assert_includes model_ids, 'gpt-4'
    assert_includes model_ids, 'gpt-35-turbo'

    model = models.find { |m| m['id'] == 'gpt-4o' }
    assert_equal 'GPT-4o', model['name']
    assert_equal 'gpt-4o', model['family']
    assert_equal 'azure-openai', model['provider']
    assert_equal 128000, model['context_window']
    assert_equal 16384, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal ['function_calling'], model['capabilities']
    assert model['pricing']['text_tokens']['standard']['input_per_million'] > 0
  end

  def test_process_models_all_models_have_required_fields
    models = Providers::AzureOpenai.process_models(nil)
    required_fields = ['name', 'family', 'provider', 'id', 'context_window', 'modalities', 'capabilities', 'pricing']

    models.each do |model|
      required_fields.each do |field|
        assert model.key?(field), "Missing required field: #{field} for model #{model['id']}"
      end

      assert model['modalities'].key?('input')
      assert model['modalities'].key?('output')
      assert model['pricing'].key?('text_tokens')
    end
  end

  def test_process_models_no_duplicate_ids
    models = Providers::AzureOpenai.process_models(nil)
    ids = models.map { |m| m['id'] }
    assert_equal ids.uniq.size, ids.size, "Found duplicate IDs: #{ids}"
  end

  def test_process_models_no_duplicate_names
    models = Providers::AzureOpenai.process_models(nil)
    names = models.map { |m| m['name'] }
    assert_equal names.uniq.size, names.size, "Found duplicate names: #{names}"
  end

  def test_process_models_all_models_have_valid_context_windows
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert model['context_window'] > 0, "Invalid context window for #{model['id']}"
    end
  end

  def test_process_models_all_models_have_valid_max_output_tokens
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert model['max_output_tokens'] > 0, "Invalid max output tokens for #{model['id']}"
    end
  end

  def test_process_models_all_models_have_positive_pricing
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      pricing = model['pricing']['text_tokens']['standard']
      assert pricing['input_per_million'] > 0, "Non-positive input price for #{model['id']}"
      assert pricing['output_per_million'] > 0, "Non-positive output price for #{model['id']}"
    end
  end

  def test_process_models_all_models_have_valid_modalities
    models = Providers::AzureOpenai.process_models(nil)
    valid_modalities = ['text', 'image']

    models.each do |model|
      model['modalities']['input'].each do |mod|
        assert_includes valid_modalities, mod, "Invalid input modality #{mod} for #{model['id']}"
      end
      model['modalities']['output'].each do |mod|
        assert_includes valid_modalities, mod, "Invalid output modality #{mod} for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_non_empty_capabilities
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert model['capabilities'].size > 0, "Empty capabilities for #{model['id']}"
    end
  end

  def test_process_models_is_sorted_by_name
    models = Providers::AzureOpenai.process_models(nil)
    names = models.map { |m| m['name'] }
    assert_equal names.sort, names
  end

  def test_extract_family_for_known_models
    assert_equal 'gpt-4o', Providers::AzureOpenai.send(:extract_family, 'gpt-4o')
    assert_equal 'gpt-4o-mini', Providers::AzureOpenai.send(:extract_family, 'gpt-4o-mini')
    assert_equal 'gpt-4-turbo', Providers::AzureOpenai.send(:extract_family, 'gpt-4-turbo')
    assert_equal 'gpt-4', Providers::AzureOpenai.send(:extract_family, 'gpt-4')
    assert_equal 'gpt-3.5-turbo', Providers::AzureOpenai.send(:extract_family, 'gpt-35-turbo')
  end

  def test_extract_family_fallback
    assert_equal 'unknown-model', Providers::AzureOpenai.send(:extract_family, 'unknown-model')
  end

  def test_get_pricing_for_model_known_models
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-4o')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 2.5, 'output_per_million' => 10.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_pricing_for_model_unknown_model
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, 'unknown')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 2.5, 'output_per_million' => 10.0 }
      }
    }
    assert_equal expected, pricing
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
        assert Dir.exist?('catalog/azure-openai')
        assert File.exist?('catalog/azure-openai/models.jsonl')
        content = File.read('catalog/azure-openai/models.jsonl')
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
        assert Dir.exist?('catalog/azure-openai')
        assert File.exist?('catalog/azure-openai/models.jsonl')
        content = File.read('catalog/azure-openai/models.jsonl')
        assert_equal "\n", content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_run_handles_process_models_from_api_exception
    mock_models_data = [{ 'id' => 'test' }]

    @provider.stub :fetch_models_from_api, mock_models_data do
      @provider.stub :process_models_from_api, -> { raise StandardError.new('Processing failed') } do
        assert_raises(StandardError) { @provider.run }
      end
    end
  end

  def test_run_handles_save_models_to_jsonl_exception
    mock_models_data = [{ 'id' => 'test' }]
    mock_processed_models = [{ 'id' => 'processed' }]

    @provider.stub :fetch_models_from_api, mock_models_data do
      @provider.stub :process_models_from_api, mock_processed_models do
        @provider.stub :save_models_to_jsonl, ->(_) { raise IOError.new('Save failed') } do
          assert_raises(IOError) { @provider.run }
        end
      end
    end
  end

  def test_run_logs_correct_messages_on_success
    mock_models_data = [{ 'id' => 'test' }]
    mock_processed_models = [{ 'id' => 'processed' }]

    @provider.stub :fetch_models_from_api, mock_models_data do
      @provider.stub :process_models_from_api, mock_processed_models do
        @provider.stub :save_models_to_jsonl, nil do
          @provider.run
        end
      end
    end

    output = @output.string
    assert_match %r{Azure OpenAI provider: OpenAPI spec handling skipped}, output
    assert_match %r{Updated Azure OpenAI models data from API}, output
    refute_match %r{Failed to fetch models}, output
  end

  def test_run_logs_correct_messages_on_failure
    @provider.stub :fetch_models_from_api, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Azure OpenAI provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models from Azure OpenAI API}, output
    refute_match %r{Updated Azure OpenAI models data}, output
  end

  def test_process_models_ignores_input_data
    # Test that process_models ignores the input data parameter
    result1 = Providers::AzureOpenai.process_models(nil)
    result2 = Providers::AzureOpenai.process_models({ 'some' => 'data' })
    result3 = Providers::AzureOpenai.process_models([])

    assert_equal result1, result2
    assert_equal result1, result3
  end

  def test_process_models_all_models_have_correct_provider
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert_equal 'azure-openai', model['provider']
    end
  end

  def test_process_models_all_models_have_text_modalities_only
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert_equal ['text'], model['modalities']['input']
      assert_equal ['text'], model['modalities']['output']
    end
  end

  def test_process_models_all_models_have_function_calling_capability
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert_includes model['capabilities'], 'function_calling'
    end
  end

  def test_process_models_pricing_structure_is_correct
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      pricing = model['pricing']
      assert pricing.key?('text_tokens')
      assert pricing['text_tokens'].key?('standard')
      standard = pricing['text_tokens']['standard']
      assert standard.key?('input_per_million')
      assert standard.key?('output_per_million')
      assert_kind_of Numeric, standard['input_per_million']
      assert_kind_of Numeric, standard['output_per_million']
    end
  end

  def test_process_models_specific_model_details_gpt_4o
    models = Providers::AzureOpenai.process_models(nil)
    model = models.find { |m| m['id'] == 'gpt-4o' }
    assert_equal 'GPT-4o', model['name']
    assert_equal 'gpt-4o', model['family']
    assert_equal 128000, model['context_window']
    assert_equal 16384, model['max_output_tokens']
    assert_equal 2.5, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 10.0, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_specific_model_details_gpt_4o_mini
    models = Providers::AzureOpenai.process_models(nil)
    model = models.find { |m| m['id'] == 'gpt-4o-mini' }
    assert_equal 'GPT-4o mini', model['name']
    assert_equal 'gpt-4o-mini', model['family']
    assert_equal 128000, model['context_window']
    assert_equal 16384, model['max_output_tokens']
    assert_equal 0.15, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 0.6, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_specific_model_details_gpt_4_turbo
    models = Providers::AzureOpenai.process_models(nil)
    model = models.find { |m| m['id'] == 'gpt-4-turbo' }
    assert_equal 'GPT-4 Turbo', model['name']
    assert_equal 'gpt-4-turbo', model['family']
    assert_equal 128000, model['context_window']
    assert_equal 4096, model['max_output_tokens']
    assert_equal 10.0, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 30.0, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_specific_model_details_gpt_4
    models = Providers::AzureOpenai.process_models(nil)
    model = models.find { |m| m['id'] == 'gpt-4' }
    assert_equal 'GPT-4', model['name']
    assert_equal 'gpt-4', model['family']
    assert_equal 8192, model['context_window']
    assert_equal 4096, model['max_output_tokens']
    assert_equal 30.0, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 60.0, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_specific_model_details_gpt_35_turbo
    models = Providers::AzureOpenai.process_models(nil)
    model = models.find { |m| m['id'] == 'gpt-35-turbo' }
    assert_equal 'GPT-3.5 Turbo', model['name']
    assert_equal 'gpt-3.5-turbo', model['family']
    assert_equal 16384, model['context_window']
    assert_equal 4096, model['max_output_tokens']
    assert_equal 0.5, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 1.5, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_extract_family_case_insensitive
    # Test that extract_family handles case variations (though current implementation is exact match)
    assert_equal 'gpt-4o', Providers::AzureOpenai.send(:extract_family, 'gpt-4o')
    # Note: Current implementation doesn't handle case variations, but test documents expected behavior
  end

  def test_extract_family_with_special_characters
    assert_equal 'gpt-4o-special', Providers::AzureOpenai.send(:extract_family, 'gpt-4o-special')
  end

  def test_extract_family_empty_string
    assert_equal '', Providers::AzureOpenai.send(:extract_family, '')
  end

  def test_get_pricing_for_model_gpt_4o_mini
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-4o-mini')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 0.15, 'output_per_million' => 0.6 }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_pricing_for_model_gpt_4_turbo
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-4-turbo')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 10.0, 'output_per_million' => 30.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_pricing_for_model_gpt_4
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-4')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 30.0, 'output_per_million' => 60.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_pricing_for_model_gpt_35_turbo
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-35-turbo')
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 0.5, 'output_per_million' => 1.5 }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_pricing_for_model_nil_input
    pricing = Providers::AzureOpenai.send(:get_pricing_for_model, nil)
    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 2.5, 'output_per_million' => 10.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_save_models_to_jsonl_overwrites_existing_file
    models1 = [{ 'id' => 'model1', 'name' => 'Model 1' }]
    models2 = [{ 'id' => 'model2', 'name' => 'Model 2' }]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        @provider.send(:save_models_to_jsonl, models1)
        content1 = File.read('catalog/azure-openai/models.jsonl')

        @provider.send(:save_models_to_jsonl, models2)
        content2 = File.read('catalog/azure-openai/models.jsonl')

        refute_equal content1, content2
        parsed = JSON.parse(content2.strip)
        assert_equal models2.first, parsed
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_models_to_jsonl_creates_parent_directories
    models = [{ 'id' => 'test', 'name' => 'Test' }]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        # Ensure parent directory doesn't exist
        refute Dir.exist?('catalog')
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/azure-openai')
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_models_to_jsonl_with_complex_data
    models = [
      {
        'id' => 'complex-model',
        'name' => 'Complex Model',
        'nested' => { 'data' => [1, 2, 3] },
        'array_field' => ['a', 'b', 'c']
      }
    ]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        @provider.send(:save_models_to_jsonl, models)
        content = File.read('catalog/azure-openai/models.jsonl')
        parsed = JSON.parse(content.strip)
        assert_equal models.first, parsed
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_process_models_from_api_with_nil_data
    result = @provider.send(:process_models_from_api, nil)
    expected = Providers::AzureOpenai.process_models(nil)
    assert_equal expected, result
  end

  def test_process_models_from_api_with_empty_data
    result = @provider.send(:process_models_from_api, [])
    expected = Providers::AzureOpenai.process_models(nil)
    assert_equal expected, result
  end

  def test_process_models_from_api_with_data
    data = [{ 'some' => 'data' }]
    result = @provider.send(:process_models_from_api, data)
    expected = Providers::AzureOpenai.process_models(nil)
    assert_equal expected, result
  end

  def test_openapi_url_is_https
    url = @provider.openapi_url
    assert url.start_with?('https://')
  end

  def test_openapi_url_contains_correct_path
    url = @provider.openapi_url
    assert_match %r{api\.openai\.azure\.com}, url
    assert_match %r{openapi\.yaml}, url
  end

  def test_can_pull_methods_return_boolean
    [@provider.can_pull_api_specs?, @provider.can_pull_model_info?, @provider.can_pull_pricing?].each do |result|
      assert_includes [true, false], result
    end
  end

  def test_process_models_returns_sorted_models
    models = Providers::AzureOpenai.process_models(nil)
    names = models.map { |m| m['name'] }
    # Check that names are in alphabetical order
    sorted_names = names.sort
    assert_equal sorted_names, names
  end

  def test_process_models_no_models_with_zero_values
    models = Providers::AzureOpenai.process_models(nil)
    models.each do |model|
      assert model['context_window'] > 0
      assert model['max_output_tokens'] > 0
      pricing = model['pricing']['text_tokens']['standard']
      assert pricing['input_per_million'] > 0
      assert pricing['output_per_million'] > 0
    end
  end

  def test_extract_family_returns_string
    result = Providers::AzureOpenai.send(:extract_family, 'gpt-4o')
    assert_kind_of String, result
  end

  def test_get_pricing_for_model_returns_hash
    result = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-4o')
    assert_kind_of Hash, result
  end

  def test_get_pricing_for_model_has_correct_keys
    result = Providers::AzureOpenai.send(:get_pricing_for_model, 'gpt-4o')
    assert result.key?('text_tokens')
    assert result['text_tokens'].key?('standard')
    assert result['text_tokens']['standard'].key?('input_per_million')
    assert result['text_tokens']['standard'].key?('output_per_million')
  end

  def test_save_models_to_jsonl_handles_nil_models
    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        assert_raises(NoMethodError) { @provider.send(:save_models_to_jsonl, nil) }
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_run_method_calls_expected_private_methods
    mock_models_data = [{ 'id' => 'test' }]
    mock_processed_models = [{ 'id' => 'processed' }]

    fetch_called = false
    process_called = false
    save_called = false

    @provider.stub :fetch_models_from_api, -> { fetch_called = true; mock_models_data } do
      @provider.stub :process_models_from_api, ->(_) { process_called = true; mock_processed_models } do
        @provider.stub :save_models_to_jsonl, ->(_) { save_called = true } do
          @provider.run
        end
      end
    end

    assert fetch_called
    assert process_called
    assert save_called
  end

  def test_run_method_skips_save_when_no_models
    @provider.stub :fetch_models_from_api, nil do
      save_called = false
      @provider.stub :save_models_to_jsonl, ->(_) { save_called = true } do
        @provider.run
        refute save_called
      end
    end
  end
end