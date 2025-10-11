require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/deepseek'
require_relative '../lib/colored_logger'

class TestDeepseek < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Deepseek.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Deepseek.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Deepseek.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
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
    expected_url = 'https://raw.githubusercontent.com/api-evangelist/deepseek/refs/heads/main/openapi/deepseek-chat-completion-api-openapi.yml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_successful_download_and_save
    mock_spec_content = "openapi: 3.0.0\ninfo:\n  title: DeepSeek API\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Downloading Deepseek OpenAPI spec}, output
    assert_match %r{Updated Deepseek OpenAPI spec}, output
    assert_match %r{Deepseek models data update skipped}, output
  end

  def test_run_handles_download_failure
    @provider.stub :download_openapi_spec, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Downloading Deepseek OpenAPI spec}, output
    assert_match %r{Failed to download OpenAPI spec from}, output
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

  def test_process_models_returns_correct_structure
    models = @provider.send(:process_models, nil)
    assert_kind_of Array, models
    assert_equal 3, models.size

    model_ids = models.map { |m| m['id'] }
    assert_includes model_ids, 'deepseek-chat'
    assert_includes model_ids, 'deepseek-coder'
    assert_includes model_ids, 'deepseek-reasoner'

    model = models.find { |m| m['id'] == 'deepseek-chat' }
    assert_equal 'DeepSeek Chat', model['name']
    assert_equal 'deepseek-chat', model['family']
    assert_equal 'deepseek', model['provider']
    assert_equal 128000, model['context_window']
    assert_equal 8192, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal ['function_calling', 'structured_output'], model['capabilities']
    refute_nil model['pricing']
    refute_nil model['pricing'][:text_tokens]
    refute_nil model['pricing'][:text_tokens][:standard]
    assert model['pricing'][:text_tokens][:standard][:input_per_million] > 0
  end

  def test_process_models_all_models_have_required_fields
    models = @provider.send(:process_models, nil)
    required_fields = ['name', 'family', 'provider', 'id', 'context_window', 'modalities', 'capabilities', 'pricing']

    models.each do |model|
      required_fields.each do |field|
        assert model.key?(field), "Missing required field: #{field} for model #{model['id']}"
      end

      assert model['modalities'].key?('input')
      assert model['modalities'].key?('output')
      # pricing is present
    end
  end

  def test_process_models_no_duplicate_ids
    models = @provider.send(:process_models, nil)
    ids = models.map { |m| m['id'] }
    assert_equal ids.uniq.size, ids.size, "Found duplicate IDs: #{ids}"
  end

  def test_process_models_all_models_have_valid_context_windows
    models = @provider.send(:process_models, nil)
    models.each do |model|
      assert model['context_window'] > 0, "Invalid context window for #{model['id']}"
    end
  end

  def test_process_models_all_models_have_valid_max_output_tokens
    models = @provider.send(:process_models, nil)
    models.each do |model|
      assert model['max_output_tokens'] > 0, "Invalid max output tokens for #{model['id']}"
    end
  end

  def test_process_models_all_models_have_positive_pricing
    models = @provider.send(:process_models, nil)
    models.each do |model|
      next unless model['pricing'] && model['pricing'][:text_tokens] && model['pricing'][:text_tokens][:standard]
      pricing = model['pricing'][:text_tokens][:standard]
      assert pricing[:input_per_million] > 0, "Non-positive input price for #{model['id']}"
      assert pricing[:output_per_million] > 0, "Non-positive output price for #{model['id']}"
    end
  end

  def test_process_models_all_models_have_valid_modalities
    models = @provider.send(:process_models, nil)
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
    models = @provider.send(:process_models, nil)
    models.each do |model|
      assert model['capabilities'].size > 0, "Empty capabilities for #{model['id']}"
    end
  end
end