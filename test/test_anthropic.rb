require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/anthropic'
require_relative '../lib/colored_logger'
require_relative '../lib/fetchers/anthropic'

class TestAnthropic < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Anthropic.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Anthropic.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Anthropic.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
  end

  def test_can_pull_api_specs_returns_true
    assert @provider.can_pull_api_specs?
  end

  def test_can_pull_model_info_returns_true
    assert @provider.can_pull_model_info?
  end

  def test_can_pull_pricing_returns_true
    assert @provider.can_pull_pricing?
  end

  def test_openapi_url_returns_correct_url
    expected_url = 'https://storage.googleapis.com/stainless-sdk-openapi-specs/anthropic%2Fanthropic-9c7d1ea59095c76b24f14fe279825c2b0dc10f165a973a46b8a548af9aeda62e.yml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_successful_download_and_save
    mock_spec_content = "openapi: 3.0.0\ninfo:\n  title: Anthropic API\n"
    mock_processed_models = [
      {
        'name' => 'Claude Opus 4',
        'family' => 'claude-opus-4',
        'provider' => 'anthropic',
        'id' => 'claude-opus-4-20250514',
        'context_window' => 200000,
        'max_output_tokens' => 32000,
        'modalities' => { 'input' => ['text', 'image'], 'output' => ['text'] },
        'capabilities' => ['function_calling'],
        'pricing' => {
          'text_tokens' => {
            'standard' => { 'input_per_million' => 15.0, 'output_per_million' => 75.0 },
            'cached' => { 'input_per_million' => 18.75, 'output_per_million' => 75.0 }
          }
        }
      }
    ]

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :process_models, mock_processed_models do
          @provider.stub :save_models_to_jsonl, nil do
            @provider.run
          end
        end
      end
    end

    output = @output.string
    assert_match %r{Downloading Anthropic OpenAPI spec}, output
    assert_match %r{Updated Anthropic OpenAPI spec}, output
    assert_match %r{Updated Anthropic models data using fetcher}, output
  end

  def test_run_handles_download_failure
    @provider.stub :download_openapi_spec, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Downloading Anthropic OpenAPI spec}, output
    assert_match %r{Failed to download OpenAPI spec from}, output
  end

  def test_run_handles_empty_fetched_data
    mock_spec_content = "openapi: 3.0.0\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :process_models, [] do
          @provider.run
        end
      end
    end

    output = @output.string
    assert_match %r{Downloading Anthropic OpenAPI spec}, output
    assert_match %r{Updated Anthropic OpenAPI spec}, output
    assert_match %r{Failed to fetch models using fetcher, skipping update}, output
  end

  def test_run_handles_nil_fetched_data
    mock_spec_content = "openapi: 3.0.0\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :process_models, nil do
          @provider.run
        end
      end
    end

    output = @output.string
    assert_match %r{Downloading Anthropic OpenAPI spec}, output
    assert_match %r{Updated Anthropic OpenAPI spec}, output
    assert_match %r{Failed to fetch models using fetcher, skipping update}, output
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
        assert Dir.exist?('catalog/anthropic')
        assert File.exist?('catalog/anthropic/models.jsonl')
        content = File.read('catalog/anthropic/models.jsonl')
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
        assert Dir.exist?('catalog/anthropic')
        assert File.exist?('catalog/anthropic/models.jsonl')
        content = File.read('catalog/anthropic/models.jsonl')
        assert_equal "\n", content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_process_models_with_empty_fetched_data
    Fetchers::Anthropic.stub :fetch, [] do
      result = @provider.send(:process_models)
      assert_empty result
    end
  end

  def test_process_models_with_nil_fetched_data
    Fetchers::Anthropic.stub :fetch, nil do
      result = @provider.send(:process_models)
      assert_empty result
    end
  end

  def test_process_models_with_valid_data
    mock_fetched_data = [
      { name: 'Claude Opus 4', api_name: 'claude-opus-4-20250514', input_price: 15.0, output_price: 75.0 },
      { name: 'Claude Sonnet 4', api_name: 'claude-sonnet-4-20250514', input_price: 3.0, output_price: 15.0 },
      { name: 'Claude 3.5 Haiku', api_name: 'claude-3-5-haiku-20241022', input_price: 0.8, output_price: 4.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      assert_kind_of Array, result
      assert_equal 3, result.size
    end
  end

  def test_process_models_filters_out_models_without_api_name
    mock_fetched_data = [
      { name: 'Valid Model', api_name: 'claude-valid-1' },
      { name: 'Invalid Model', api_name: nil },
      { name: 'Another Valid', api_name: 'claude-valid-2' }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      assert_equal 2, result.size
      api_names = result.map { |m| m['id'] }
      assert_includes api_names, 'claude-valid-1'
      assert_includes api_names, 'claude-valid-2'
    end
  end

  def test_process_models_sorts_by_name
    mock_fetched_data = [
      { name: 'Z Model', api_name: 'claude-z' },
      { name: 'A Model', api_name: 'claude-a' },
      { name: 'M Model', api_name: 'claude-m' }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      names = result.map { |m| m['name'] }
      assert_equal names.sort, names
    end
  end

  def test_process_models_structure_for_opus_4_model
    mock_fetched_data = [
      { name: 'Claude Opus 4', api_name: 'claude-opus-4-20250514', input_price: 15.0, output_price: 75.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 'Claude Opus 4', model['name']
      assert_equal 'claude-opus-4', model['family']
      assert_equal 'anthropic', model['provider']
      assert_equal 'claude-opus-4-20250514', model['id']
      assert_equal 200000, model['context_window']
      assert_equal 32000, model['max_output_tokens']
      assert_equal ['text', 'image'], model['modalities']['input']
      assert_equal ['text'], model['modalities']['output']
      assert_equal ['function_calling'], model['capabilities']
      assert model['pricing']['text_tokens']['standard']['input_per_million'] > 0
      assert model['pricing']['text_tokens']['standard']['output_per_million'] > 0
    end
  end

  def test_process_models_structure_for_sonnet_4_model
    mock_fetched_data = [
      { name: 'Claude Sonnet 4', api_name: 'claude-sonnet-4-20250514', input_price: 3.0, output_price: 15.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 'claude-sonnet-4', model['family']
      assert_equal 200000, model['context_window']
      assert_equal 64000, model['max_output_tokens']
    end
  end

  def test_process_models_structure_for_3_7_sonnet_model
    mock_fetched_data = [
      { name: 'Claude 3.7 Sonnet', api_name: 'claude-3-7-sonnet-20250219', input_price: 3.0, output_price: 15.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 'claude-3-7-sonnet', model['family']
      assert_equal 200000, model['context_window']
      assert_equal 64000, model['max_output_tokens']
    end
  end

  def test_process_models_structure_for_3_5_haiku_model
    mock_fetched_data = [
      { name: 'Claude 3.5 Haiku', api_name: 'claude-3-5-haiku-20241022', input_price: 0.8, output_price: 4.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 'claude-3-5-haiku', model['family']
      assert_equal 200000, model['context_window']
      assert_equal 8192, model['max_output_tokens']
    end
  end

  def test_process_models_structure_for_3_haiku_model
    mock_fetched_data = [
      { name: 'Claude 3 Haiku', api_name: 'claude-3-haiku-20240307', input_price: 0.25, output_price: 1.25 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 'claude-3-haiku', model['family']
      assert_equal 200000, model['context_window']
      assert_equal 4096, model['max_output_tokens']
    end
  end

  def test_process_models_uses_default_name_when_nil
    mock_fetched_data = [
      { name: nil, api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 'claude-test', model['name']
    end
  end

  def test_get_model_specs_returns_default_specs
    specs = @provider.send(:get_model_specs, 'unknown-model')
    assert_equal 200000, specs[:context_window]
    assert_equal 4096, specs[:max_output_tokens]
  end

  def test_get_model_specs_returns_specific_specs_for_known_models
    test_cases = {
      'claude-opus-4-1-20250805' => { context_window: 200000, max_output_tokens: 32000 },
      'claude-opus-4-20250514' => { context_window: 200000, max_output_tokens: 32000 },
      'claude-sonnet-4-20250514' => { context_window: 200000, max_output_tokens: 64000 },
      'claude-3-7-sonnet-20250219' => { context_window: 200000, max_output_tokens: 64000 },
      'claude-3-5-haiku-20241022' => { context_window: 200000, max_output_tokens: 8192 },
      'claude-3-haiku-20240307' => { context_window: 200000, max_output_tokens: 4096 }
    }

    test_cases.each do |api_name, expected_specs|
      specs = @provider.send(:get_model_specs, api_name)
      assert_equal expected_specs[:context_window], specs[:context_window], "Failed for #{api_name}"
      assert_equal expected_specs[:max_output_tokens], specs[:max_output_tokens], "Failed for #{api_name}"
    end
  end

  def test_build_pricing_with_all_prices_provided
    model = { input_price: 3.0, output_price: 15.0, cache_write_price: 4.0, cache_hit_price: 12.0 }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 3.0, 'output_per_million' => 15.0 },
        'cached' => { 'input_per_million' => 4.0, 'output_per_million' => 12.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_with_default_prices
    model = {}
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 3.0, 'output_per_million' => 15.0 },
        'cached' => { 'input_per_million' => 3.75, 'output_per_million' => 15.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_calculates_cache_prices_when_not_provided
    model = { input_price: 2.0, output_price: 10.0 }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => { 'input_per_million' => 2.0, 'output_per_million' => 10.0 },
        'cached' => { 'input_per_million' => 2.5, 'output_per_million' => 10.0 }
      }
    }
    assert_equal expected, pricing
  end

  def test_extract_family_for_opus_4_1
    assert_equal 'claude-opus-4-1', @provider.send(:extract_family, 'claude-opus-4-1-20250805')
  end

  def test_extract_family_for_opus_4
    assert_equal 'claude-opus-4', @provider.send(:extract_family, 'claude-opus-4-20250514')
  end

  def test_extract_family_for_sonnet_4
    assert_equal 'claude-sonnet-4', @provider.send(:extract_family, 'claude-sonnet-4-20250514')
  end

  def test_extract_family_for_3_7_sonnet
    assert_equal 'claude-3-7-sonnet', @provider.send(:extract_family, 'claude-3-7-sonnet-20250219')
  end

  def test_extract_family_for_3_5_haiku
    assert_equal 'claude-3-5-haiku', @provider.send(:extract_family, 'claude-3-5-haiku-20241022')
  end

  def test_extract_family_for_3_haiku
    assert_equal 'claude-3-haiku', @provider.send(:extract_family, 'claude-3-haiku-20240307')
  end

  def test_extract_family_fallback
    assert_equal 'claude-instant', @provider.send(:extract_family, 'claude-instant-1.2')
    assert_equal 'claude-2', @provider.send(:extract_family, 'claude-2-100k')
  end

  def test_process_models_all_models_have_required_fields
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first

      required_fields = ['name', 'family', 'provider', 'id', 'context_window', 'modalities', 'capabilities', 'pricing']
      required_fields.each do |field|
        assert model.key?(field), "Missing required field: #{field}"
      end

      assert model['modalities'].key?('input')
      assert model['modalities'].key?('output')
      assert model['pricing'].key?('text_tokens')
    end
  end

  def test_process_models_no_duplicate_ids
    mock_fetched_data = [
      { name: 'Model 1', api_name: 'claude-test-1' },
      { name: 'Model 2', api_name: 'claude-test-2' },
      { name: 'Model 3', api_name: 'claude-test-3' }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      ids = result.map { |m| m['id'] }
      assert_equal ids.uniq.size, ids.size, "Found duplicate IDs: #{ids}"
    end
  end

  def test_process_models_no_duplicate_names
    mock_fetched_data = [
      { name: 'Unique Model 1', api_name: 'claude-test-1' },
      { name: 'Unique Model 2', api_name: 'claude-test-2' }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      names = result.map { |m| m['name'] }
      assert_equal names.uniq.size, names.size, "Found duplicate names: #{names}"
    end
  end

  def test_process_models_all_models_have_valid_context_windows
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      result.each do |model|
        assert model['context_window'] > 0, "Invalid context window for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_valid_max_output_tokens
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      result.each do |model|
        if model['max_output_tokens']
          assert model['max_output_tokens'] > 0, "Invalid max output tokens for #{model['id']}"
        end
      end
    end
  end

  def test_process_models_all_models_have_positive_pricing
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      result.each do |model|
        pricing = model['pricing']['text_tokens']['standard']
        assert pricing['input_per_million'] > 0, "Non-positive input price for #{model['id']}"
        assert pricing['output_per_million'] > 0, "Non-positive output price for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_valid_modalities
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      valid_modalities = ['text', 'image']

      result.each do |model|
        model['modalities']['input'].each do |mod|
          assert_includes valid_modalities, mod, "Invalid input modality #{mod} for #{model['id']}"
        end
        model['modalities']['output'].each do |mod|
          assert_includes valid_modalities, mod, "Invalid output modality #{mod} for #{model['id']}"
        end
      end
    end
  end

  def test_process_models_all_models_have_non_empty_capabilities
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      result.each do |model|
        assert model['capabilities'].size > 0, "Empty capabilities for #{model['id']}"
      end
    end
  end

  def test_process_models_handles_models_with_missing_prices
    mock_fetched_data = [
      { name: 'Test Model', api_name: 'claude-test' } # no prices
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      pricing = model['pricing']['text_tokens']['standard']
      assert_equal 3.0, pricing['input_per_million'] # default
      assert_equal 15.0, pricing['output_per_million'] # default
    end
  end

  def test_run_handles_save_spec_failure
    mock_spec_content = "openapi: 3.0.0\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, -> { raise StandardError.new('Save failed') } do
        assert_raises StandardError do
          @provider.run
        end
      end
    end
  end

  def test_run_handles_process_models_failure
    mock_spec_content = "openapi: 3.0.0\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :process_models, -> { raise StandardError.new('Process failed') } do
          assert_raises StandardError do
            @provider.run
          end
        end
      end
    end
  end

  def test_run_handles_save_models_failure
    mock_spec_content = "openapi: 3.0.0\n"
    mock_processed_models = [{ 'id' => 'test' }]

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :process_models, mock_processed_models do
          @provider.stub :save_models_to_jsonl, -> { raise StandardError.new('Save models failed') } do
            assert_raises StandardError do
              @provider.run
            end
          end
        end
      end
    end
  end

  def test_process_models_compacts_nil_entries
    mock_fetched_data = [
      { name: 'Valid Model', api_name: 'claude-valid' },
      { name: 'Invalid Model', api_name: nil }, # should be filtered out
      { name: 'Another Valid', api_name: 'claude-another' }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      # Should only have 2 models, nil api_name filtered out
      assert_equal 2, result.size
      result.each do |model|
        refute_nil model['id']
      end
    end
  end

  def test_process_models_handles_empty_model_data
    mock_fetched_data = [{}]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      assert_empty result
    end
  end

  def test_process_models_handles_mixed_valid_invalid_data
    mock_fetched_data = [
      { name: 'Valid 1', api_name: 'claude-valid-1', input_price: 1.0 },
      { name: 'Invalid', api_name: nil },
      { name: 'Valid 2', api_name: 'claude-valid-2', output_price: 2.0 },
      { name: 'Invalid 2', api_name: '' },
      { name: 'Valid 3', api_name: 'claude-valid-3' }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      assert_equal 3, result.size
      valid_ids = ['claude-valid-1', 'claude-valid-2', 'claude-valid-3']
      result.each do |model|
        assert_includes valid_ids, model['id']
      end
    end
  end
end

class TestFetchersAnthropic < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @fetcher = Fetchers::Anthropic.new(logger: @logger)
    @logger.level = Logger::DEBUG  # Override the WARN level set by the fetcher for testing
  end

  def test_initialization_with_default_logger
    fetcher = Fetchers::Anthropic.new
    assert_kind_of ColoredLogger, fetcher.logger
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    fetcher = Fetchers::Anthropic.new(logger: custom_logger)
    assert_equal custom_logger, fetcher.logger
  end

  def test_initialization_sets_logger_level_to_warn
    fetcher = Fetchers::Anthropic.new(logger: @logger)
    assert_equal Logger::WARN, fetcher.logger.level
  end

  def test_class_fetch_with_default_options
    mock_result = [{ name: 'Test Model', api_name: 'claude-test' }]
    Fetchers::Anthropic.any_instance.expects(:fetch).returns(mock_result)
    result = Fetchers::Anthropic.fetch
    assert_equal mock_result, result
  end

  def test_class_fetch_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    mock_result = [{ name: 'Test Model', api_name: 'claude-test' }]
    Fetchers::Anthropic.any_instance.expects(:fetch).returns(mock_result)
    result = Fetchers::Anthropic.fetch(logger: custom_logger)
    assert_equal mock_result, result
  end

  def test_class_fetch_creates_instance_with_options
    custom_logger = Logger.new(STDOUT)
    mock_instance = Minitest::Mock.new
    mock_instance.expect(:fetch, [])
    Fetchers::Anthropic.stub(:new, mock_instance) do
      result = Fetchers::Anthropic.fetch(logger: custom_logger)
      assert_equal [], result
    end
    mock_instance.verify
  end

  def test_fetch_combines_models_and_pricing_successfully
    models_data = [
      { name: 'Claude Opus', api_name: 'claude-opus-4' },
      { name: 'Claude Sonnet', api_name: 'claude-sonnet-4' }
    ]
    pricing_data = {
      'claude-opus-4' => { input_price: 15.0, output_price: 75.0 },
      'claude-sonnet-4' => { input_price: 3.0, output_price: 15.0 }
    }
    expected = [
      { name: 'Claude Opus', api_name: 'claude-opus-4', input_price: 15.0, output_price: 75.0 },
      { name: 'Claude Sonnet', api_name: 'claude-sonnet-4', input_price: 3.0, output_price: 15.0 }
    ]

    @fetcher.stub(:fetch_models, models_data) do
      @fetcher.stub(:fetch_pricing, pricing_data) do
        result = @fetcher.fetch
        assert_equal expected, result
      end
    end
  end

  def test_fetch_returns_empty_array_when_models_empty
    @fetcher.stub(:fetch_models, []) do
      @fetcher.stub(:fetch_pricing, {}) do
        result = @fetcher.fetch
        assert_empty result
      end
    end
  end

  def test_fetch_filters_out_models_without_api_name
    models_data = [
      { name: 'Valid Model', api_name: 'claude-valid' },
      { name: 'Invalid Model', api_name: nil },
      { name: 'Another Valid', api_name: 'claude-another' }
    ]
    pricing_data = {
      'claude-valid' => { input_price: 1.0 },
      'claude-another' => { input_price: 2.0 }
    }

    @fetcher.stub(:fetch_models, models_data) do
      @fetcher.stub(:fetch_pricing, pricing_data) do
        result = @fetcher.fetch
        assert_equal 2, result.size
        api_names = result.map { |m| m[:api_name] }
        assert_includes api_names, 'claude-valid'
        assert_includes api_names, 'claude-another'
      end
    end
  end

  def test_fetch_logs_successful_fetch_count
    models_data = [{ name: 'Test Model', api_name: 'claude-test' }]
    pricing_data = {}

    @fetcher.stub(:fetch_models, models_data) do
      @fetcher.stub(:fetch_pricing, pricing_data) do
        @fetcher.fetch
        output = @output.string
        assert_match %r{Successfully fetched 1 models}, output
      end
    end
  end

  def test_fetch_handles_fetch_models_error
    @fetcher.stub(:fetch_models, -> { raise StandardError.new('Models fetch failed') }) do
      result = @fetcher.fetch
      assert_empty result
      output = @output.string
      assert_match %r{Failed to fetch Anthropic data: StandardError - Models fetch failed}, output
    end
  end

  def test_fetch_handles_fetch_pricing_error
    models_data = [{ name: 'Test Model', api_name: 'claude-test' }]

    @fetcher.stub(:fetch_models, models_data) do
      @fetcher.stub(:fetch_pricing, -> { raise StandardError.new('Pricing fetch failed') }) do
        result = @fetcher.fetch
        assert_empty result
        output = @output.string
        assert_match %r{Failed to fetch Anthropic data: StandardError - Pricing fetch failed}, output
      end
    end
  end

  def test_fetch_handles_unexpected_error
    @fetcher.stub(:fetch_models, -> { raise RuntimeError.new('Unexpected error') }) do
      result = @fetcher.fetch
      assert_empty result
      output = @output.string
      assert_match %r{Failed to fetch Anthropic data: RuntimeError - Unexpected error}, output
    end
  end

  def test_fetch_returns_empty_array_on_any_error
    @fetcher.stub(:fetch_models, -> { raise 'Some error' }) do
      result = @fetcher.fetch
      assert_equal [], result
    end
  end

  def test_fetch_models_parses_table_rows_successfully
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td><td>us-east-1</td><td>us-east1</td></tr>
            <tr><td>Claude Sonnet 4</td><td>claude-sonnet-4-20250514</td><td>us-west-2</td><td>us-west2</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_equal 2, result.size
      assert_equal 'Claude Opus 4', result[0][:name]
      assert_equal 'claude-opus-4-20250514', result[0][:api_name]
      assert_equal 'us-east-1', result[0][:bedrock_name]
      assert_equal 'us-east1', result[0][:vertex_name]
    end
  end

  def test_fetch_models_skips_header_rows
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Model</td><td>API Name</td></tr>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_equal 1, result.size
      assert_equal 'Claude Opus 4', result[0][:name]
    end
  end

  def test_fetch_models_skips_empty_or_invalid_rows
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td></td><td></td></tr>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td></tr>
            <tr><td>Invalid Model</td><td>invalid-name</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_equal 1, result.size
      assert_equal 'Claude Opus 4', result[0][:name]
    end
  end

  def test_fetch_models_falls_back_to_headings
    html = <<-HTML
      <html>
        <body>
          <h2>Claude Opus 4</h2>
          <p>Some description</p>
          <code>claude-opus-4-20250514</code>
          <h3>Claude Sonnet 4</h3>
          <code>claude-sonnet-4-20250514</code>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_equal 2, result.size
      names = result.map { |m| m[:name] }
      assert_includes names, 'Claude Opus 4'
      assert_includes names, 'Claude Sonnet 4'
    end
  end

  def test_fetch_models_deduplicates_by_api_name
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td></tr>
            <tr><td>Claude Opus 4 (Duplicate)</td><td>claude-opus-4-20250514</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_equal 1, result.size
      assert_equal 'Claude Opus 4', result[0][:name]
    end
  end

  def test_fetch_models_logs_extracted_count
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      @fetcher.send(:fetch_models)
      output = @output.string
      assert_match %r{Extracted 1 unique models}, output
    end
  end

  def test_fetch_models_returns_empty_array_when_fetch_html_fails
    @fetcher.stub(:fetch_html, nil) do
      result = @fetcher.send(:fetch_models)
      assert_empty result
    end
  end

  def test_fetch_models_handles_table_parsing_errors
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    # Mock css to raise an error
    doc.stub(:css, ->(*args) { raise StandardError.new('CSS parsing failed') }) do
      @fetcher.stub(:fetch_html, doc) do
        result = @fetcher.send(:fetch_models)
        assert_empty result
        output = @output.string
        assert_match %r{Error in fetch_models: StandardError - CSS parsing failed}, output
      end
    end
  end

  def test_fetch_models_handles_row_parsing_errors
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Claude Opus 4</td><td>claude-opus-4-20250514</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    # Mock row to raise an error
    mock_row = mock('row')
    mock_row.stubs(:css).raises(StandardError.new('Row parsing failed'))
    mock_row.stubs(:text).returns('dummy')
    doc.stubs(:css).returns([mock_row])
    @fetcher.stubs(:fetch_html).returns(doc)
    result = @fetcher.send(:fetch_models)
    # Should continue processing despite error
    assert_empty result
    output = @output.string
    assert_match %r{Error parsing model row: Row parsing failed}, output
  end

  def test_fetch_models_handles_heading_parsing_errors
    html = <<-HTML
      <html>
        <body>
          <h2>Claude Opus 4</h2>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    # Mock heading to raise an error
    mock_heading = mock('heading')
    mock_heading.stubs(:text).raises(StandardError.new('Heading parsing failed'))
    mock_heading.stubs(:css).returns([])
    doc.stubs(:css).returns([mock_heading])
    @fetcher.stubs(:fetch_html).returns(doc)
    result = @fetcher.send(:fetch_models)
    assert_empty result
    output = @output.string
    assert_match %r{Error extracting text: Heading parsing failed}, output
  end

  def test_fetch_models_returns_empty_array_on_unexpected_error
    @fetcher.stubs(:fetch_html).raises(RuntimeError.new('Unexpected fetch error'))
    result = @fetcher.send(:fetch_models)
    assert_empty result
    output = @output.string
    assert_match %r{Error in fetch_models: RuntimeError - Unexpected fetch error}, output
  end

  def test_fetch_models_handles_empty_table
    html = <<-HTML
      <html>
        <body>
          <table></table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_empty result
    end
  end

  def test_fetch_models_handles_table_without_rows
    html = <<-HTML
      <html>
        <body>
          <table>
            <thead><tr><th>Header</th></tr></thead>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_models)
      assert_empty result
    end
  end

  def test_fetch_pricing_parses_pricing_table_successfully
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th><th>Output</th></tr>
            <tr><td>Claude Opus 4</td><td>$15 / MTok</td><td>$75 / MTok</td></tr>
            <tr><td>Claude Sonnet 4</td><td>$3 / MTok</td><td>$15 / MTok</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_pricing)
      assert_equal 2, result.size
      assert_equal 15.0, result['claude-opus-4'][:input_price]
      assert_equal 75.0, result['claude-opus-4'][:output_price]
      assert_equal 3.0, result['claude-sonnet-4'][:input_price]
      assert_equal 15.0, result['claude-sonnet-4'][:output_price]
    end
  end

  def test_fetch_pricing_skips_non_pricing_tables
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Feature</th><th>Description</th></tr>
            <tr><td>Some Feature</td><td>Description</td></tr>
          </table>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_pricing)
      assert_equal 1, result.size
      assert_equal 15.0, result['claude-opus-4'][:input_price]
    end
  end

  def test_fetch_pricing_skips_header_rows_in_data
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Model</td><td>Price</td></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_pricing)
      assert_equal 1, result.size
    end
  end

  def test_fetch_pricing_handles_multiple_tables
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
          <table>
            <tr><th>Model</th><th>Output</th></tr>
            <tr><td>Claude Sonnet 4</td><td>$75</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_pricing)
      assert_equal 2, result.size
    end
  end

  def test_fetch_pricing_logs_extracted_count
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      @fetcher.send(:fetch_pricing)
      output = @output.string
      assert_match %r{Extracted pricing for 1 models}, output
    end
  end

  def test_fetch_pricing_returns_empty_hash_when_fetch_html_fails
    @fetcher.stub(:fetch_html, nil) do
      result = @fetcher.send(:fetch_pricing)
      assert_empty result
    end
  end

  def test_fetch_pricing_handles_table_parsing_errors
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    doc.stub(:css, ->(*args) { raise StandardError.new('Table parsing failed') }) do
      @fetcher.stub(:fetch_html, doc) do
        result = @fetcher.send(:fetch_pricing)
        assert_empty result
        output = @output.string
        assert_match %r{Error in fetch_pricing: StandardError - Table parsing failed}, output
      end
    end
  end

  def test_fetch_pricing_handles_row_parsing_errors
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    mock_table = mock('table')
    mock_table.stubs(:css).raises(StandardError.new('Row parsing failed'))
    doc.stubs(:css).returns([mock_table])
    @fetcher.stubs(:fetch_html).returns(doc)
    result = @fetcher.send(:fetch_pricing)
    assert_empty result
    output = @output.string
    assert_match %r{Error parsing pricing table: Row parsing failed}, output
  end

  def test_fetch_pricing_handles_pricing_extraction_errors
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><th>Model</th><th>Input</th></tr>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:extract_api_name_from_text, ->(*args) { raise StandardError.new('API name extraction failed') }) do
      @fetcher.stub(:fetch_html, doc) do
        result = @fetcher.send(:fetch_pricing)
        assert_empty result
        output = @output.string
        assert_match %r{Error parsing pricing row: API name extraction failed}, output
      end
    end
  end

  def test_fetch_pricing_returns_empty_hash_on_unexpected_error
    @fetcher.stubs(:fetch_html).raises(RuntimeError.new('Unexpected pricing error'))
    result = @fetcher.send(:fetch_pricing)
    assert_empty result
    output = @output.string
    assert_match %r{Error in fetch_pricing: RuntimeError - Unexpected pricing error}, output
  end

  def test_fetch_pricing_handles_empty_tables
    html = <<-HTML
      <html>
        <body>
          <table></table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_pricing)
      assert_empty result
    end
  end

  def test_fetch_pricing_handles_tables_without_headers
    html = <<-HTML
      <html>
        <body>
          <table>
            <tr><td>Claude Opus 4</td><td>$15</td></tr>
          </table>
        </body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    @fetcher.stub(:fetch_html, doc) do
      result = @fetcher.send(:fetch_pricing)
      assert_empty result
    end
  end

  def test_fetch_html_successful_request
    html_content = '<html><body><h1>Test</h1></body></html>'
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns(html_content)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_kind_of Nokogiri::HTML::Document, result
    assert_equal 'Test', result.css('h1').text
  end

  def test_fetch_html_handles_http_error
    mock_response = mock('response')
    mock_response.expects(:success?).returns(false)
    mock_response.expects(:status).returns(404)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    output = @output.string
    assert_match %r{Failed to fetch test page: HTTP 404 for test page}, output
  end

  def test_fetch_html_handles_empty_response_body
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns('')
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    output = @output.string
    assert_match %r{Failed to fetch test page: Empty response body for test page}, output
  end

  def test_fetch_html_handles_nil_response_body
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns(nil)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
  end

  def test_fetch_html_handles_invalid_html
    invalid_html = '<html><body><unclosed>'
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns(invalid_html)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    output = @output.string
    assert_match %r{Failed to fetch test page: Failed to parse HTML for test page}, output
  end

  def test_fetch_html_handles_timeout_with_retry
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).times(4).raises(Faraday::TimeoutError.new('Timeout'))

    @fetcher.stubs(:connection).returns(mock_connection)
    @fetcher.stubs(:sleep).returns(nil)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    output = @output.string
    assert_match %r{Max retries reached for test page}, output
  end

  def test_fetch_html_handles_timeout_success_after_retry
    html_content = '<html><body>Success</body></html>'
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns(html_content)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_kind_of Nokogiri::HTML::Document, result
  end

  def test_fetch_html_handles_faraday_error
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).raises(Faraday::Error.new('Connection failed'))

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    output = @output.string
    assert_match %r{Failed to fetch test page: Connection failed}, output
  end

  def test_fetch_html_handles_unexpected_error
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).raises(RuntimeError.new('Unexpected error'))

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    output = @output.string
    assert_match %r{Unexpected error fetching test page: RuntimeError - Unexpected error}, output
  end

  def test_fetch_html_logs_debug_message
    html_content = '<html><body>Test</body></html>'
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns(html_content)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    @fetcher.send(:fetch_html, Fetchers::Anthropic::MODELS_URL, 'test page')
    output = @output.string
    assert_match %r{Fetching test page from}, output
  end

  def test_connection_returns_http_cache_instance
    connection = @fetcher.send(:connection)
    assert_kind_of HttpCache, connection
  end

  def test_connection_memoizes_instance
    conn1 = @fetcher.send(:connection)
    conn2 = @fetcher.send(:connection)
    assert_same conn1, conn2
  end

  def test_extract_pricing_info_with_input_output_headers
    # Create real Nokogiri elements for testing
    doc = Nokogiri::HTML('<table><tr><td>Claude Opus 4</td><td>$15</td><td>$75</td></tr></table>')
    cells = doc.css('td')
    headers = ['', 'Input', 'Output']
    result = @fetcher.send(:extract_pricing_info, cells, headers)
    expected = { input_price: 15.0, output_price: 75.0 }
    assert_equal expected, result
  end

  def test_extract_pricing_info_with_position_based_fallback
    doc = Nokogiri::HTML('<table><tr><td>Claude Opus 4</td><td>$10</td><td>$20</td><td>$30</td></tr></table>')
    cells = doc.css('td')
    headers = ['', 'Price1', 'Price2', 'Price3']
    result = @fetcher.send(:extract_pricing_info, cells, headers)
    expected = { input_price: 10.0, cache_write_price: 20.0, output_price: 30.0 }
    assert_equal expected, result
  end

  def test_extract_pricing_info_handles_invalid_prices
    doc = Nokogiri::HTML('<table><tr><td>Claude Opus 4</td><td>invalid</td><td>$75</td></tr></table>')
    cells = doc.css('td')
    headers = ['', 'Input', 'Output']
    result = @fetcher.send(:extract_pricing_info, cells, headers)
    expected = { output_price: 75.0 }
    assert_equal expected, result
  end

  def test_determine_price_key_with_input_headers
    assert_equal :input_price, @fetcher.send(:determine_price_key, 'input', 1, 3)
    assert_equal :input_price, @fetcher.send(:determine_price_key, 'base input', 1, 3)
  end

  def test_determine_price_key_with_output_headers
    assert_equal :output_price, @fetcher.send(:determine_price_key, 'output', 2, 3)
  end

  def test_determine_price_key_with_cache_write_headers
    assert_equal :cache_write_price, @fetcher.send(:determine_price_key, 'cache write', 2, 4)
    assert_equal :cache_write_price, @fetcher.send(:determine_price_key, 'write cache', 2, 4)
  end

  def test_determine_price_key_with_cache_hit_headers
    assert_equal :cache_hit_price, @fetcher.send(:determine_price_key, 'cache hit', 3, 4)
    assert_equal :cache_hit_price, @fetcher.send(:determine_price_key, 'refresh', 3, 4)
  end

  def test_determine_price_key_with_position_fallback
    # First data column (index 1) -> input_price
    assert_equal :input_price, @fetcher.send(:determine_price_key, 'unknown', 1, 3)
    # Second data column (index 2) -> cache_write_price
    assert_equal :cache_write_price, @fetcher.send(:determine_price_key, 'unknown', 2, 4)
    # Last column -> output_price
    assert_equal :output_price, @fetcher.send(:determine_price_key, 'unknown', 3, 4)
    # Second to last column -> cache_hit_price
    assert_equal :cache_hit_price, @fetcher.send(:determine_price_key, 'unknown', 3, 5)
  end

  def test_determine_price_key_returns_nil_for_unknown
    assert_nil @fetcher.send(:determine_price_key, 'unknown', 3, 6)
  end

  def test_safe_text_with_valid_element
    doc = Nokogiri::HTML('<div>  Test Text  </div>')
    element = doc.css('div').first
    result = @fetcher.send(:safe_text, element)
    assert_equal 'Test Text', result
  end

  def test_safe_text_with_nil_element
    result = @fetcher.send(:safe_text, nil)
    assert_equal '', result
  end

  def test_safe_text_normalizes_whitespace
    doc = Nokogiri::HTML('<div>Test

Text		With  Spaces</div>')
    element = doc.css('div').first
    result = @fetcher.send(:safe_text, element)
    assert_equal 'Test Text With Spaces', result
  end

  def test_header_row_detects_model_headers
    assert @fetcher.send(:header_row?, 'Model')
    assert @fetcher.send(:header_row?, 'model')
    assert @fetcher.send(:header_row?, 'MODEL')
  end

  def test_header_row_detects_name_headers
    assert @fetcher.send(:header_row?, 'Name')
    assert @fetcher.send(:header_row?, 'name')
  end

  def test_header_row_detects_api_headers
    assert @fetcher.send(:header_row?, 'API')
    assert @fetcher.send(:header_row?, 'api')
  end

  def test_header_row_detects_feature_headers
    assert @fetcher.send(:header_row?, 'Feature')
    assert @fetcher.send(:header_row?, 'feature')
  end

  def test_header_row_returns_false_for_regular_content
    refute @fetcher.send(:header_row?, 'Claude Opus 4')
    refute @fetcher.send(:header_row?, 'claude-opus-4-20250514')
    refute @fetcher.send(:header_row?, 'Some other text')
  end

  def test_header_row_handles_case_insensitive_matching
    assert @fetcher.send(:header_row?, 'MODEL NAME')
    assert @fetcher.send(:header_row?, 'Api Name')
  end

  def test_valid_api_name_accepts_valid_names
    assert @fetcher.send(:valid_api_name?, 'claude-opus-4-20250514')
    assert @fetcher.send(:valid_api_name?, 'claude-sonnet-4-20250514')
    assert @fetcher.send(:valid_api_name?, 'claude-3-5-haiku-20241022')
  end

  def test_valid_api_name_rejects_nil
    refute @fetcher.send(:valid_api_name?, nil)
  end

  def test_valid_api_name_rejects_empty_string
    refute @fetcher.send(:valid_api_name?, '')
  end

  def test_valid_api_name_rejects_non_claude_prefix
    refute @fetcher.send(:valid_api_name?, 'gpt-4')
    refute @fetcher.send(:valid_api_name?, 'some-other-model')
  end

  def test_valid_api_name_rejects_names_with_spaces
    refute @fetcher.send(:valid_api_name?, 'claude opus 4')
    refute @fetcher.send(:valid_api_name?, 'claude-opus 4')
  end

  def test_valid_api_name_rejects_short_names
    refute @fetcher.send(:valid_api_name?, 'claude')
    refute @fetcher.send(:valid_api_name?, 'claude-')
  end

  def test_extract_price_with_dollar_sign
    assert_equal 15.0, @fetcher.send(:extract_price, '$15')
    assert_equal 3.5, @fetcher.send(:extract_price, '$3.50')
  end

  def test_extract_price_without_dollar_sign
    assert_equal 15.0, @fetcher.send(:extract_price, '15')
    assert_equal 3.5, @fetcher.send(:extract_price, '3.50')
  end

  def test_extract_price_with_per_unit_text
    assert_equal 15.0, @fetcher.send(:extract_price, '$15 / MTok')
    assert_equal 3.0, @fetcher.send(:extract_price, '3.00 per million tokens')
  end

  def test_extract_price_with_commas_and_spaces
    assert_equal 1500.0, @fetcher.send(:extract_price, '$1,500')
    assert_equal 15.0, @fetcher.send(:extract_price, '$ 15 ')
  end

  def test_extract_price_returns_nil_for_zero
    assert_nil @fetcher.send(:extract_price, '$0')
    assert_nil @fetcher.send(:extract_price, '0.0')
  end

  def test_extract_price_returns_nil_for_negative
    assert_nil @fetcher.send(:extract_price, '$-5')
    assert_nil @fetcher.send(:extract_price, '-10')
  end

  def test_extract_price_returns_nil_for_no_numbers
    assert_nil @fetcher.send(:extract_price, 'no price')
    assert_nil @fetcher.send(:extract_price, 'free')
  end

  def test_extract_price_returns_nil_for_nil_input
    assert_nil @fetcher.send(:extract_price, nil)
  end

  def test_extract_price_returns_nil_for_empty_string
    assert_nil @fetcher.send(:extract_price, '')
  end

  def test_extract_price_handles_regex_error
    bad_text = '$15'.dup
    bad_text.define_singleton_method(:gsub) { |*args| raise StandardError.new('Regex failed') }
    result = @fetcher.send(:extract_price, bad_text)
    assert_nil result
    output = @output.string
    assert_match %r{Error extracting price from '\$15': Regex failed}, output
  end

  def test_extract_api_name_from_text_with_valid_api_name
    assert_equal 'claude-opus-4-20250514', @fetcher.send(:extract_api_name_from_text, 'claude-opus-4-20250514')
  end

  def test_extract_api_name_from_text_opus_4
    assert_equal 'claude-opus-4', @fetcher.send(:extract_api_name_from_text, 'Claude Opus 4')
    assert_equal 'claude-opus-4', @fetcher.send(:extract_api_name_from_text, 'OPUS 4.0 model')
  end

  def test_extract_api_name_from_text_sonnet_4
    assert_equal 'claude-sonnet-4', @fetcher.send(:extract_api_name_from_text, 'Claude Sonnet 4')
    assert_equal 'claude-sonnet-4', @fetcher.send(:extract_api_name_from_text, 'SONNET 4.0')
  end

  def test_extract_api_name_from_text_haiku_35
    assert_equal 'claude-3-5-haiku', @fetcher.send(:extract_api_name_from_text, 'Claude 3.5 Haiku')
    assert_equal 'claude-3-5-haiku', @fetcher.send(:extract_api_name_from_text, 'HAIKU 3.5')
  end

  def test_extract_api_name_from_text_haiku_3
    assert_equal 'claude-3-haiku', @fetcher.send(:extract_api_name_from_text, 'Claude 3 Haiku')
    assert_equal 'claude-3-haiku', @fetcher.send(:extract_api_name_from_text, 'HAIKU 3.0')
  end

  def test_extract_api_name_from_text_sonnet_37
    assert_equal 'claude-3-7-sonnet', @fetcher.send(:extract_api_name_from_text, 'Claude 3.7 Sonnet')
  end

  def test_extract_api_name_from_text_returns_nil_for_invalid_version
    assert_nil @fetcher.send(:extract_api_name_from_text, 'Claude Opus 0')
    assert_nil @fetcher.send(:extract_api_name_from_text, 'Invalid 4')
  end

  def test_extract_api_name_from_text_returns_nil_for_no_match
    assert_nil @fetcher.send(:extract_api_name_from_text, 'Some random text')
    assert_nil @fetcher.send(:extract_api_name_from_text, 'GPT-4')
  end

  def test_extract_api_name_from_text_returns_nil_for_nil_input
    assert_nil @fetcher.send(:extract_api_name_from_text, nil)
  end

  def test_extract_api_name_from_text_returns_nil_for_empty_string
    assert_nil @fetcher.send(:extract_api_name_from_text, '')
  end

  def test_extract_api_name_from_text_handles_error
    bad_text = 'Claude Opus 4'.dup
    def bad_text.match(*args)
      raise StandardError.new('Regex failed')
    end
    result = @fetcher.send(:extract_api_name_from_text, bad_text)
    assert_equal 'claude-opus-4', result
    # The method handles the error internally and returns the expected result
  end

  def test_extract_api_name_with_code_block_sibling
    heading = mock_element('Claude Opus 4')
    code_element = mock_element('claude-opus-4-20250514')
    code_element.define_singleton_method(:name) { 'code' }
    code_element.define_singleton_method(:css) { |selector| selector == 'code' ? [code_element] : [] }
    heading.define_singleton_method(:next_element) { code_element }
    code_element.define_singleton_method(:next_element) { nil }

    result = @fetcher.send(:extract_api_name, heading)
    assert_equal 'claude-opus-4-20250514', result
  end

  def test_extract_api_name_with_nested_code_in_sibling
    heading = mock_element('Claude Opus 4')
    sibling = mock_element('')
    code_element = mock_element('claude-opus-4-20250514')
    sibling.define_singleton_method(:name) { 'p' }
    sibling.define_singleton_method(:css) { |selector| selector == 'code' ? [code_element] : [] }
    heading.define_singleton_method(:next_element) { sibling }
    sibling.define_singleton_method(:next_element) { nil }

    result = @fetcher.send(:extract_api_name, heading)
    assert_equal 'claude-opus-4-20250514', result
  end

  def test_extract_api_name_stops_at_next_heading
    heading = mock_element('Claude Opus 4')
    sibling = mock_element('')
    sibling.define_singleton_method(:name) { 'h3' }
    heading.define_singleton_method(:next_element) { sibling }

    result = @fetcher.send(:extract_api_name, heading)
    assert_nil result
  end

  def test_extract_api_name_skips_invalid_api_names
    heading = mock_element('Claude Opus 4')
    code_element = mock_element('invalid-name')
    code_element.define_singleton_method(:name) { 'code' }
    code_element.define_singleton_method(:css) { |selector| selector == 'code' ? [code_element] : [] }
    heading.define_singleton_method(:next_element) { code_element }
    code_element.define_singleton_method(:next_element) { nil }

    result = @fetcher.send(:extract_api_name, heading)
    assert_nil result
  end

  def test_extract_api_name_returns_nil_when_no_code_found
    heading = mock_element('Claude Opus 4')
    sibling = mock_element('Some text')
    sibling.define_singleton_method(:name) { 'p' }
    sibling.define_singleton_method(:css) { |selector| selector == 'code' ? [] : [] }
    heading.define_singleton_method(:next_element) { sibling }
    sibling.define_singleton_method(:next_element) { nil }

    result = @fetcher.send(:extract_api_name, heading)
    assert_nil result
  end

  def test_extract_api_name_returns_nil_for_nil_element
    result = @fetcher.send(:extract_api_name, nil)
    assert_nil result
  end

  def test_extract_api_name_handles_traversal_error
    heading = mock_element('Claude Opus 4')
    heading.define_singleton_method(:next_element) { raise StandardError.new('Traversal failed') }

    result = @fetcher.send(:extract_api_name, heading)
    assert_nil result
    output = @output.string
    assert_match %r{Error extracting API name from element: Traversal failed}, output
  end

  def test_extract_api_name_limits_depth
    heading = mock_element('Claude Opus 4')
    # Create a chain of siblings that exceeds max_depth (10)
    siblings = []
    12.times do |i|
      sibling = mock_element('')
      sibling.define_singleton_method(:name) { 'p' }
      sibling.define_singleton_method(:css) { |selector| selector == 'code' ? [] : [] }
      siblings << sibling
    end

    # Chain them together
    siblings.each_with_index do |sibling, i|
      if i < 11
        sibling.define_singleton_method(:next_element) { siblings[i + 1] }
      else
        sibling.define_singleton_method(:next_element) { nil }
      end
    end

    heading.define_singleton_method(:next_element) { siblings[0] }

    result = @fetcher.send(:extract_api_name, heading)
    assert_nil result
  end

  private

  def mock_element(text)
    element = Object.new
    element.define_singleton_method(:text) { text }
    element.define_singleton_method(:name) { 'div' }
    element.define_singleton_method(:css) { |*args| [] }
    element.define_singleton_method(:next_element) { nil }
    element
  end
end