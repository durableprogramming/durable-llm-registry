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

  def test_process_models_prefers_fetched_specs
    # When the fetcher supplies context_window/max_output_tokens (as the
    # markdown parser now does), those win over the static spec map.
    mock_fetched_data = [
      { name: 'Claude Opus 4.8', api_name: 'claude-opus-4-8', input_price: 5.0, output_price: 25.0,
        context_window: 1_000_000, max_output_tokens: 128_000 }
    ]

    Fetchers::Anthropic.stub :fetch, mock_fetched_data do
      result = @provider.send(:process_models)
      model = result.first
      assert_equal 1_000_000, model['context_window']
      assert_equal 128_000, model['max_output_tokens']
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

  # A trimmed sample of the Markdown served at MODELS_URL. The tables are
  # transposed: feature labels run down the first column, models across the top.
  MODELS_MARKDOWN = <<~MD
    # Models overview

    ### Claude Fable 5 and Claude Mythos 5

    | Feature | Claude Fable 5 | Claude Mythos 5 |
    |:--------|:-------------|:-------------|
    | **Claude API ID** | `claude-fable-5` | `claude-mythos-5` |
    | **AWS Bedrock ID** | anthropic.claude-fable-5 | Limited availability |
    | **Vertex AI ID** | claude-fable-5 | Limited availability |
    | **Context window** | <Tooltip tooltipContent="x">1M tokens</Tooltip> | <Tooltip tooltipContent="x">1M tokens</Tooltip> |
    | **Max output** | 128k tokens | 128k tokens |
    | **Pricing** | $10 / $50 per MTok (input / output) | $10 / $50 per MTok (input / output) |

    ### Latest models comparison

    | Feature | Claude Opus 4.8 | Claude Sonnet 4.6 | Claude Haiku 4.5 |
    |:--------|:-------------|:------------------|:-----------------|
    | **Claude API ID** | claude-opus-4-8 | claude-sonnet-4-6 | claude-haiku-4-5-20251001 |
    | **Claude API alias** | claude-opus-4-8 | claude-sonnet-4-6 | claude-haiku-4-5 |
    | **AWS Bedrock ID** | anthropic.claude-opus-4-8<sup>3</sup> | anthropic.claude-sonnet-4-6 | anthropic.claude-haiku-4-5-20251001-v1:0 |
    | **Vertex AI ID** | claude-opus-4-8 | claude-sonnet-4-6 | claude-haiku-4-5@20251001 |
    | **Pricing**<sup>1</sup> | \\$5 / input MTok<br/>\\$25 / output MTok | \\$3 / input MTok<br/>\\$15 / output MTok | \\$1 / input MTok<br/>\\$5 / output MTok |
    | **Context window** | <Tooltip tooltipContent="x">1M tokens</Tooltip><sup>4</sup> | <Tooltip tooltipContent="x">1M tokens</Tooltip> | <Tooltip tooltipContent="x">200k tokens</Tooltip> |
    | **Max output** | 128k tokens | 64k tokens | 64k tokens |

    <section title="Legacy models">

    | Feature | Claude Opus 4.5 | Claude Opus 4.1 (deprecated) |
    |:--------|:----------------|:----------------|
    | **Claude API ID** | claude-opus-4-5-20251101 | claude-opus-4-1-20250805 |
    | **AWS Bedrock ID** | anthropic.claude-opus-4-5-20251101-v1:0 | anthropic.claude-opus-4-1-20250805-v1:0 |
    | **Vertex AI ID** | claude-opus-4-5@20251101 | claude-opus-4-1@20250805 |
    | **Pricing** | \\$5 / input MTok<br/>\\$25 / output MTok | \\$15 / input MTok<br/>\\$75 / output MTok |
    | **Context window** | <Tooltip tooltipContent="x">200k tokens</Tooltip> | <Tooltip tooltipContent="x">200k tokens</Tooltip> |
    | **Max output** | 64k tokens | 32k tokens |

    </section>
  MD

  def parsed
    @fetcher.send(:parse_models, MODELS_MARKDOWN)
  end

  def model(api_name)
    parsed.find { |m| m[:api_name] == api_name }
  end

  def test_fetch_returns_parsed_models
    @fetcher.stub(:fetch_text, MODELS_MARKDOWN) do
      result = @fetcher.fetch
      api_names = result.map { |m| m[:api_name] }
      assert_includes api_names, 'claude-opus-4-8'
      assert_includes api_names, 'claude-fable-5'
      assert_includes api_names, 'claude-opus-4-1-20250805'
    end
  end

  def test_fetch_logs_successful_fetch_count
    @fetcher.stub(:fetch_text, MODELS_MARKDOWN) do
      @fetcher.fetch
      assert_match %r{Successfully fetched \d+ models}, @output.string
    end
  end

  def test_fetch_returns_empty_array_when_markdown_blank
    @fetcher.stub(:fetch_text, '') do
      assert_empty @fetcher.fetch
    end
  end

  def test_fetch_returns_empty_array_when_fetch_text_nil
    @fetcher.stub(:fetch_text, nil) do
      assert_empty @fetcher.fetch
    end
  end

  def test_fetch_handles_unexpected_error
    @fetcher.stub(:fetch_text, ->(*) { raise RuntimeError.new('boom') }) do
      result = @fetcher.fetch
      assert_empty result
      assert_match %r{Failed to fetch Anthropic data: RuntimeError - boom}, @output.string
    end
  end

  def test_parse_models_extracts_all_models
    # 2 (Fable/Mythos) + 3 (latest) + 2 (legacy) = 7
    assert_equal 7, parsed.size
  end

  def test_parse_models_prefers_id_row_over_alias
    # Haiku's id row carries the dated id; the alias row carries the dateless
    # one. We key on the id row.
    assert model('claude-haiku-4-5-20251001')
    refute model('claude-haiku-4-5')
  end

  def test_parse_models_extracts_dateless_ids
    m = model('claude-opus-4-8')
    assert_equal 'Claude Opus 4.8', m[:name]
  end

  def test_parse_models_strips_deprecated_suffix_from_name
    m = model('claude-opus-4-1-20250805')
    assert_equal 'Claude Opus 4.1', m[:name]
  end

  def test_parse_models_extracts_bedrock_and_vertex_ids
    m = model('claude-haiku-4-5-20251001')
    assert_equal 'anthropic.claude-haiku-4-5-20251001-v1:0', m[:bedrock_name]
    assert_equal 'claude-haiku-4-5@20251001', m[:vertex_name]
  end

  def test_parse_models_strips_sup_footnotes_from_bedrock_id
    m = model('claude-opus-4-8')
    assert_equal 'anthropic.claude-opus-4-8', m[:bedrock_name]
  end

  def test_parse_models_extracts_split_pricing
    m = model('claude-opus-4-8')
    assert_equal 5.0, m[:input_price]
    assert_equal 25.0, m[:output_price]
  end

  def test_parse_models_extracts_combined_pricing
    m = model('claude-fable-5')
    assert_equal 10.0, m[:input_price]
    assert_equal 50.0, m[:output_price]
  end

  def test_parse_models_extracts_context_window
    assert_equal 1_000_000, model('claude-opus-4-8')[:context_window]
    assert_equal 200_000, model('claude-haiku-4-5-20251001')[:context_window]
  end

  def test_parse_models_extracts_max_output
    assert_equal 128_000, model('claude-opus-4-8')[:max_output_tokens]
    assert_equal 64_000, model('claude-sonnet-4-6')[:max_output_tokens]
    assert_equal 32_000, model('claude-opus-4-1-20250805')[:max_output_tokens]
  end

  def test_parse_models_strips_sup_from_context_window
    # Opus 4.8's context cell carries a "<sup>4</sup>" footnote marker.
    assert_equal 1_000_000, model('claude-opus-4-8')[:context_window]
  end

  def test_parse_models_deduplicates_by_api_name
    md = MODELS_MARKDOWN + <<~MD

      | Feature | Claude Opus 4.8 |
      |:--------|:----------------|
      | **Claude API ID** | claude-opus-4-8 |
    MD
    result = @fetcher.send(:parse_models, md)
    assert_equal 1, result.count { |m| m[:api_name] == 'claude-opus-4-8' }
  end

  def test_parse_models_ignores_tables_without_id_row
    md = <<~MD
      | Feature | Foo | Bar |
      |:--------|:----|:----|
      | **Latency** | Fast | Slow |
    MD
    assert_empty @fetcher.send(:parse_models, md)
  end

  def test_parse_models_handles_markdown_without_tables
    assert_empty @fetcher.send(:parse_models, "# Heading\n\nNo tables here.\n")
  end

  def test_parse_token_count_handles_m_and_k
    assert_equal 1_000_000, @fetcher.send(:parse_token_count, '1M tokens')
    assert_equal 200_000, @fetcher.send(:parse_token_count, '200k tokens')
    assert_equal 128_000, @fetcher.send(:parse_token_count, '128k tokens')
  end

  def test_parse_token_count_strips_tags
    assert_equal 1_000_000, @fetcher.send(:parse_token_count, '<Tooltip x>1M tokens</Tooltip>')
  end

  def test_parse_token_count_returns_nil_for_blank
    assert_nil @fetcher.send(:parse_token_count, nil)
    assert_nil @fetcher.send(:parse_token_count, '')
    assert_nil @fetcher.send(:parse_token_count, 'unknown')
  end

  def test_parse_pricing_cell_split_form
    input, output = @fetcher.send(:parse_pricing_cell, '\\$5 / input MTok<br/>\\$25 / output MTok')
    assert_equal 5.0, input
    assert_equal 25.0, output
  end

  def test_parse_pricing_cell_combined_form
    input, output = @fetcher.send(:parse_pricing_cell, '$10 / $50 per MTok (input / output)')
    assert_equal 10.0, input
    assert_equal 50.0, output
  end

  def test_parse_pricing_cell_handles_blank
    assert_equal [nil, nil], @fetcher.send(:parse_pricing_cell, nil)
    assert_equal [nil, nil], @fetcher.send(:parse_pricing_cell, '')
  end

  def test_clean_id_strips_markers
    assert_equal 'claude-opus-4-8', @fetcher.send(:clean_id, '`claude-opus-4-8`')
    assert_equal 'anthropic.claude-opus-4-8', @fetcher.send(:clean_id, 'anthropic.claude-opus-4-8<sup>3</sup>')
    assert_equal '', @fetcher.send(:clean_id, nil)
  end

  def test_clean_model_name_strips_deprecated_and_markers
    assert_equal 'Claude Opus 4.1', @fetcher.send(:clean_model_name, 'Claude Opus 4.1 (deprecated)')
    assert_equal 'Claude Opus 4.8', @fetcher.send(:clean_model_name, '**Claude Opus 4.8**')
  end

  def test_normalize_label_strips_bold_and_footnotes
    assert_equal 'claude api id', @fetcher.send(:normalize_label, '**Claude API ID**')
    assert_equal 'pricing', @fetcher.send(:normalize_label, '**Pricing**<sup>1</sup>')
  end

  def test_normalize_label_strips_markdown_links
    label = '**[Extended thinking](/docs/en/build-with-claude/extended-thinking)**'
    assert_equal 'extended thinking', @fetcher.send(:normalize_label, label)
  end

  def test_valid_api_name_accepts_valid_names
    assert @fetcher.send(:valid_api_name?, 'claude-opus-4-8')
    assert @fetcher.send(:valid_api_name?, 'claude-haiku-4-5-20251001')
  end

  def test_valid_api_name_rejects_invalid
    refute @fetcher.send(:valid_api_name?, nil)
    refute @fetcher.send(:valid_api_name?, '')
    refute @fetcher.send(:valid_api_name?, 'gpt-4')
    refute @fetcher.send(:valid_api_name?, 'claude opus 4')
  end

  def test_connection_returns_http_cache_instance
    assert_kind_of HttpCache, @fetcher.send(:connection)
  end

  def test_connection_memoizes_instance
    assert_same @fetcher.send(:connection), @fetcher.send(:connection)
  end

  def test_fetch_text_successful_request
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns('hello').at_least_once
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_text, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_equal 'hello', result
  end

  def test_fetch_text_handles_http_error
    mock_response = mock('response')
    mock_response.expects(:success?).returns(false)
    mock_response.expects(:status).returns(404)
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_text, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    assert_match %r{Failed to fetch test page: HTTP 404 for test page}, @output.string
  end

  def test_fetch_text_handles_empty_body
    mock_response = mock('response')
    mock_response.expects(:success?).returns(true)
    mock_response.expects(:body).returns('').at_least_once
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).returns(mock_response)

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_text, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    assert_match %r{Empty response body for test page}, @output.string
  end

  def test_fetch_text_handles_timeout_with_retry
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).times(4).raises(Faraday::TimeoutError.new('Timeout'))

    @fetcher.stubs(:connection).returns(mock_connection)
    @fetcher.stubs(:sleep).returns(nil)
    result = @fetcher.send(:fetch_text, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    assert_match %r{Max retries reached for test page}, @output.string
  end

  def test_fetch_text_handles_faraday_error
    mock_connection = mock('connection')
    mock_connection.expects(:get).with(Fetchers::Anthropic::MODELS_URL).raises(Faraday::Error.new('Connection failed'))

    @fetcher.stubs(:connection).returns(mock_connection)
    result = @fetcher.send(:fetch_text, Fetchers::Anthropic::MODELS_URL, 'test page')
    assert_nil result
    assert_match %r{Failed to fetch test page: Connection failed}, @output.string
  end
end
