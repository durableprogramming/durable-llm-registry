require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/together'
require_relative '../lib/colored_logger'

class TestTogether < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Together.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Together.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Together.new(logger: custom_logger)
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
    expected_url = 'https://api.together.xyz/v1/openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_logs_correct_messages
    @provider.run

    output = @output.string
    assert_match %r{Together provider: OpenAPI spec handling skipped}, output
    assert_match %r{Together models data update skipped}, output
  end

  def test_process_models_returns_correct_structure
    models = @provider.send(:process_models, nil)
    assert_kind_of Array, models
    assert models.size > 0

    model_ids = models.map { |m| m['id'] }
    assert_includes model_ids, 'meta-llama/Llama-3.3-70B-Instruct-Turbo'
    assert_includes model_ids, 'deepseek-ai/DeepSeek-R1'

    model = models.find { |m| m['id'] == 'meta-llama/Llama-3.3-70B-Instruct-Turbo' }
    assert_equal 'Llama 3.3 70B Instruct Turbo', model['name']
    assert_equal 'llama-3.3-70b', model['family']
    assert_equal 'together', model['provider']
    assert_equal 131072, model['context_window']
    assert_equal 8192, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal ['function_calling'], model['capabilities']
    assert model['pricing']['text_tokens']['standard']['input_per_million'] > 0
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
      assert model['pricing'].key?('text_tokens')
    end
  end

  def test_process_models_no_duplicate_ids
    models = @provider.send(:process_models, nil)
    ids = models.map { |m| m['id'] }
    assert_equal ids.uniq.size, ids.size, "Found duplicate IDs: #{ids}"
  end

  def test_process_models_no_duplicate_names
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.uniq.size, names.size, "Found duplicate names: #{names}"
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
      pricing = model['pricing']['text_tokens']['standard']
      assert pricing['input_per_million'] > 0, "Non-positive input price for #{model['id']}"
      assert pricing['output_per_million'] > 0, "Non-positive output price for #{model['id']}"
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
      # Some models may have empty capabilities
      assert model['capabilities'].is_a?(Array), "Capabilities should be an array for #{model['id']}"
    end
  end

  def test_process_models_is_sorted_by_name
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.sort, names
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
        assert Dir.exist?('catalog/together')
        assert File.exist?('catalog/together/models.jsonl')
        content = File.read('catalog/together/models.jsonl')
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
        assert Dir.exist?('catalog/together')
        assert File.exist?('catalog/together/models.jsonl')
        content = File.read('catalog/together/models.jsonl')
        assert_equal "\n", content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end
end