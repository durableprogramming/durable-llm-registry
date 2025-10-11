require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/cohere'
require_relative '../lib/colored_logger'

class TestCohere < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Cohere.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Cohere.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Cohere.new(logger: custom_logger)
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
    expected_url = 'https://raw.githubusercontent.com/cohere-ai/cohere-developer-experience/refs/heads/main/cohere-openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_successful_download_and_save
    mock_spec_content = "openapi: 3.0.0\ninfo:\n  title: Cohere API\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :fetch_models_from_api, nil do
          @provider.run
        end
      end
    end

    output = @output.string
    assert_match %r{Downloading Cohere OpenAPI spec}, output
    assert_match %r{Updated Cohere OpenAPI spec}, output
    assert_match %r{Failed to fetch models from Cohere API, skipping update to preserve manually created data}, output
  end

  def test_run_handles_download_failure
    @provider.stub :download_openapi_spec, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Downloading Cohere OpenAPI spec}, output
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

  def test_run_with_models_data_success
    mock_spec_content = "openapi: 3.0.0\n"
    mock_models_data = [{'id' => 'test-model'}]

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.stub :fetch_models_from_api, mock_models_data do
          @provider.stub :process_models_from_api, [] do
            @provider.stub :save_models_to_jsonl, nil do
              @provider.run
            end
          end
        end
      end
    end

    output = @output.string
    assert_match %r{Updated Cohere models data from API}, output
  end

  def test_fetch_models_from_api_returns_nil
    assert_nil @provider.send(:fetch_models_from_api)
  end

  def test_save_models_to_jsonl_creates_directory_and_file
    models = [
      {'id' => 'test-model-1', 'name' => 'Test Model 1'},
      {'id' => 'test-model-2', 'name' => 'Test Model 2'}
    ]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/cohere')
        assert File.exist?('catalog/cohere/models.jsonl')
        content = File.read('catalog/cohere/models.jsonl')
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
        assert Dir.exist?('catalog/cohere')
        assert File.exist?('catalog/cohere/models.jsonl')
        content = File.read('catalog/cohere/models.jsonl')
        assert_equal "\n", content  # Just a newline for empty array
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_process_models_from_api_calls_process_models_with_nil
    @provider.stub :process_models, [] do
      result = @provider.send(:process_models_from_api, nil)
      assert_empty result
    end
  end

  def test_process_models_returns_expected_number_of_models
    models = @provider.send(:process_models, nil)
    assert_kind_of Array, models
    assert_equal 19, models.size  # Count from the hardcoded list
  end

  def test_process_models_includes_all_expected_model_ids
    models = @provider.send(:process_models, nil)
    ids = models.map { |m| m['id'] }
    expected_ids = [
      'command-a-03-2025',
      'command-a-reasoning-08-2025',
      'command-a-translate-08-2025',
      'command-a-vision-07-2025',
      'command-r7b-12-2024',
      'command-r-08-2024',
      'command-r-plus-08-2024',
      'embed-v4.0',
      'embed-english-v3.0',
      'embed-english-light-v3.0',
      'embed-multilingual-v3.0',
      'embed-multilingual-light-v3.0',
      'rerank-v3.5',
      'rerank-english-v3.0',
      'rerank-multilingual-v3.0',
      'c4ai-aya-expanse-8b',
      'c4ai-aya-expanse-32b',
      'c4ai-aya-vision-8b',
      'c4ai-aya-vision-32b'
    ]
    assert_equal expected_ids.sort, ids.sort
  end

  def test_process_models_sorts_by_name
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.sort, names
  end

  def test_process_models_structure_for_command_a_model
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'command-a-03-2025' }
    assert_equal 'Command A 03-2025', model['name']
    assert_equal 'command-a', model['family']
    assert_equal 'cohere', model['provider']
    assert_equal 256000, model['context_window']
    assert_equal 8000, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal ['function_calling', 'tool_use', 'reasoning'], model['capabilities']
    assert model['pricing'].key?('text_tokens')
    assert_equal 15.0, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 75.0, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_structure_for_vision_model
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'command-a-vision-07-2025' }
    assert_equal ['text', 'image'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_includes model['capabilities'], 'vision'
  end

  def test_process_models_structure_for_embed_model
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'embed-v4.0' }
    assert_equal ['text', 'image'], model['modalities']['input']
    assert_equal ['embedding'], model['modalities']['output']
    assert_includes model['capabilities'], 'embedding'
    assert_nil model['max_output_tokens']
    assert model['pricing'].key?('text_tokens')
    assert_equal 0.1, model['pricing']['text_tokens']['standard']['input_per_thousand']
    assert_nil model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_structure_for_rerank_model
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'rerank-v3.5' }
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['ranking'], model['modalities']['output']
    assert_includes model['capabilities'], 'reranking'
    assert_nil model['max_output_tokens']
    assert model['pricing'].key?('search')
    assert_equal 2.0, model['pricing']['search']['per_thousand']
  end

  def test_process_models_structure_for_multilingual_embed
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'embed-multilingual-v3.0' }
    assert_includes model['capabilities'], 'multilingual'
  end

  def test_process_models_structure_for_aya_model
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'c4ai-aya-expanse-8b' }
    assert_equal 'Aya Expanse 8B', model['name']
    assert_equal 'aya-expanse', model['family']
    assert_equal 8000, model['context_window']
    assert_equal 4000, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_includes model['capabilities'], 'multilingual'
    assert_equal 0.5, model['pricing']['text_tokens']['standard']['input_per_million']
    assert_equal 1.5, model['pricing']['text_tokens']['standard']['output_per_million']
  end

  def test_process_models_structure_for_aya_vision_model
    models = @provider.send(:process_models, nil)
    model = models.find { |m| m['id'] == 'c4ai-aya-vision-8b' }
    assert_equal ['text', 'image'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_includes model['capabilities'], 'vision'
  end

  def test_process_models_compacts_nil_keys
    models = @provider.send(:process_models, nil)
    models.each do |model|
      refute_includes model.keys, nil
    end
  end

  def test_process_models_all_models_have_required_fields
    models = @provider.send(:process_models, nil)
    models.each do |model|
      assert model.key?('name')
      assert model.key?('family')
      assert model.key?('provider')
      assert model.key?('id')
      assert model.key?('context_window')
      # max_output_tokens can be nil for embed/rerank
      assert model.key?('modalities')
      assert model['modalities'].key?('input')
      assert model['modalities'].key?('output')
      assert model.key?('capabilities')
      assert model.key?('pricing')
    end
  end

  def test_process_models_pricing_logic_for_text_tokens
    models = @provider.send(:process_models, nil)
    text_models = models.select { |m| m['modalities']['output'] == ['text'] && !m['id'].include?('embed') && !m['id'].include?('rerank') }
    text_models.each do |model|
      pricing = model['pricing']
      assert pricing.key?('text_tokens')
      assert pricing['text_tokens'].key?('standard')
      assert pricing['text_tokens']['standard'].key?('input_per_million')
      assert pricing['text_tokens']['standard'].key?('output_per_million')
    end
  end

  def test_process_models_pricing_logic_for_embed_models
    models = @provider.send(:process_models, nil)
    embed_models = models.select { |m| m['id'].include?('embed') }
    embed_models.each do |model|
      pricing = model['pricing']
      assert pricing.key?('text_tokens')
      assert pricing['text_tokens'].key?('standard')
      assert pricing['text_tokens']['standard'].key?('input_per_thousand')
      assert_nil pricing['text_tokens']['standard']['output_per_million']
    end
  end

  def test_process_models_pricing_logic_for_rerank_models
    models = @provider.send(:process_models, nil)
    rerank_models = models.select { |m| m['id'].include?('rerank') }
    rerank_models.each do |model|
      pricing = model['pricing']
      assert pricing.key?('search')
      assert pricing['search'].key?('per_thousand')
      assert_nil pricing['text_tokens']
    end
  end

  def test_process_models_no_duplicate_ids
    models = @provider.send(:process_models, nil)
    ids = models.map { |m| m['id'] }
    assert_equal ids.uniq.size, ids.size
  end

  def test_process_models_no_duplicate_names
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.uniq.size, names.size
  end



  def test_process_models_handles_edge_cases
    # Test with nil input (already tested)
    models = @provider.send(:process_models, nil)
    assert_kind_of Array, models

    # Test that all models have valid pricing (no nil pricing)
    models.each do |model|
      refute_nil model['pricing']
    end
  end

  def test_all_models_have_positive_pricing_values
    models = @provider.send(:process_models, nil)
    models.each do |model|
      pricing = model['pricing']
      if pricing.key?('text_tokens')
        input_price = pricing['text_tokens']['standard']['input_per_million'] || pricing['text_tokens']['standard']['input_per_thousand']
        assert input_price > 0, "Model #{model['id']} has non-positive input price"
        output_price = pricing['text_tokens']['standard']['output_per_million']
        assert output_price.nil? || output_price > 0, "Model #{model['id']} has non-positive output price"
      elsif pricing.key?('search')
        search_price = pricing['search']['per_thousand']
        assert search_price > 0, "Model #{model['id']} has non-positive search price"
      end
    end
  end

  def test_all_models_have_valid_context_windows
    models = @provider.send(:process_models, nil)
    models.each do |model|
      assert model['context_window'] > 0, "Model #{model['id']} has invalid context window"
    end
  end

  def test_all_models_have_valid_max_output_tokens
    models = @provider.send(:process_models, nil)
    models.each do |model|
      if model['max_output_tokens']
        assert model['max_output_tokens'] > 0, "Model #{model['id']} has invalid max output tokens"
      end
    end
  end

  def test_all_models_have_non_empty_capabilities
    models = @provider.send(:process_models, nil)
    models.each do |model|
      assert model['capabilities'].size > 0, "Model #{model['id']} has empty capabilities"
    end
  end

  def test_all_models_have_valid_modalities
    models = @provider.send(:process_models, nil)
    valid_modalities = ['text', 'image', 'embedding', 'ranking']
    models.each do |model|
      model['modalities']['input'].each do |mod|
        assert_includes valid_modalities, mod, "Model #{model['id']} has invalid input modality #{mod}"
      end
      model['modalities']['output'].each do |mod|
        assert_includes valid_modalities, mod, "Model #{model['id']} has invalid output modality #{mod}"
      end
    end
  end
end