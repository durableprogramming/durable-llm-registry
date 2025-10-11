require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'json'
require 'tempfile'
require_relative '../lib/providers/opencode'
require_relative '../lib/colored_logger'

class TestOpencodeProvider < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Opencode.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Opencode.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Opencode.new(logger: custom_logger)
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

  def test_run_successful_processing
    mock_models = [
      { name: 'Test Model', api_name: 'test-model', input_price: 1.0, output_price: 2.0 }
    ]

    @provider.stub :process_models, mock_models do
      @provider.stub :save_models_to_jsonl, nil do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Updated OpenCode Zen models data using fetcher}, output
  end

  def test_run_handles_empty_models
    @provider.stub :process_models, [] do
      @provider.run
    end

    output = @output.string
    assert_match %r{Failed to fetch models using fetcher, skipping update}, output
  end

  def test_run_handles_nil_models
    @provider.stub :process_models, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Failed to fetch models using fetcher, skipping update}, output
  end

  def test_process_models_with_empty_fetched_data
    Fetchers::Opencode.stub :fetch, [] do
      result = @provider.send(:process_models)
      assert_empty result
    end
  end

  def test_process_models_filters_models_without_api_name
    fetched_data = [
      { name: 'Model 1', api_name: 'model-1' },
      { name: 'Model 2' },  # No api_name
      { name: 'Model 3', api_name: 'model-3' }
    ]

    Fetchers::Opencode.stub :fetch, fetched_data do
      result = @provider.send(:process_models)
      assert_equal 2, result.size
      assert_equal 'model-1', result[0]['id']
      assert_equal 'model-3', result[1]['id']
    end
  end

  def test_process_models_processes_single_model
    fetched_data = [
      { name: 'Test Model', api_name: 'test-model', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Opencode.stub :fetch, fetched_data do
      result = @provider.send(:process_models)
      assert_equal 1, result.size
      model = result.first
      assert_equal 'Test Model', model['name']
      assert_equal 'test-model', model['id']
      assert_equal 'opencode-zen', model['provider']
      assert model['pricing']
    end
  end

  def test_process_models_processes_multiple_models_and_sorts
    fetched_data = [
      { name: 'Z Model', api_name: 'z-model', input_price: 1.0, output_price: 2.0 },
      { name: 'A Model', api_name: 'a-model', input_price: 1.0, output_price: 2.0 }
    ]

    Fetchers::Opencode.stub :fetch, fetched_data do
      result = @provider.send(:process_models)
      assert_equal 2, result.size
      assert_equal 'A Model', result[0]['name']
      assert_equal 'Z Model', result[1]['name']
    end
  end

  def test_process_models_uses_name_fallback_to_api_name
    fetched_data = [
      { api_name: 'test-model', input_price: 1.0, output_price: 2.0 }  # No name
    ]

    Fetchers::Opencode.stub :fetch, fetched_data do
      result = @provider.send(:process_models)
      assert_equal 1, result.size
      assert_equal 'test-model', result.first['name']
    end
  end

  def test_get_model_specs_returns_default_specs
    specs = @provider.send(:get_model_specs, 'unknown-model')
    assert_equal 128000, specs[:context_window]
    assert_equal 4096, specs[:max_output_tokens]
    assert_equal ['text'], specs[:modalities]['input']
    assert_equal ['text'], specs[:modalities]['output']
    assert_includes specs[:capabilities], 'function_calling'
  end

  def test_get_model_specs_gpt_5
    specs = @provider.send(:get_model_specs, 'gpt-5')
    assert_equal 128000, specs[:context_window]
    assert_equal 16384, specs[:max_output_tokens]
    assert_equal ['text'], specs[:modalities]['input']
    assert_equal ['text'], specs[:modalities]['output']
    assert_includes specs[:capabilities], 'function_calling'
  end

  def test_get_model_specs_gpt_5_codex
    specs = @provider.send(:get_model_specs, 'gpt-5-codex')
    assert_equal 128000, specs[:context_window]
    assert_equal 16384, specs[:max_output_tokens]
  end

  def test_get_model_specs_claude_sonnet_4_5
    specs = @provider.send(:get_model_specs, 'claude-sonnet-4-5')
    assert_equal 200000, specs[:context_window]
    assert_equal 8192, specs[:max_output_tokens]
    assert_equal ['text', 'image'], specs[:modalities]['input']
    assert_equal ['text'], specs[:modalities]['output']
  end

  def test_get_model_specs_claude_sonnet_4
    specs = @provider.send(:get_model_specs, 'claude-sonnet-4')
    assert_equal 200000, specs[:context_window]
    assert_equal 8192, specs[:max_output_tokens]
    assert_equal ['text', 'image'], specs[:modalities]['input']
  end

  def test_get_model_specs_claude_3_5_haiku
    specs = @provider.send(:get_model_specs, 'claude-3-5-haiku')
    assert_equal 200000, specs[:context_window]
    assert_equal 8192, specs[:max_output_tokens]
    assert_equal ['text', 'image'], specs[:modalities]['input']
  end

  def test_get_model_specs_claude_opus_4_1
    specs = @provider.send(:get_model_specs, 'claude-opus-4-1')
    assert_equal 200000, specs[:context_window]
    assert_equal 32000, specs[:max_output_tokens]
    assert_equal ['text', 'image'], specs[:modalities]['input']
  end

  def test_get_model_specs_qwen3_coder
    specs = @provider.send(:get_model_specs, 'qwen3-coder')
    assert_equal 128000, specs[:context_window]
    assert_equal 4096, specs[:max_output_tokens]
    assert_equal ['text'], specs[:modalities]['input']
  end

  def test_get_model_specs_grok_code
    specs = @provider.send(:get_model_specs, 'grok-code')
    assert_equal 128000, specs[:context_window]
    assert_equal 4096, specs[:max_output_tokens]
  end

  def test_get_model_specs_kimi_k2
    specs = @provider.send(:get_model_specs, 'kimi-k2')
    assert_equal 128000, specs[:context_window]
    assert_equal 4096, specs[:max_output_tokens]
  end

  def test_build_pricing_with_all_prices
    model = {
      input_price: 2.0,
      output_price: 4.0,
      cache_write_price: 3.0,
      cache_hit_price: 0.5
    }
    pricing = @provider.send(:build_pricing, model)
    assert_equal 2.0, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 4.0, pricing['text_tokens']['standard']['output_per_million']
    assert_equal 3.0, pricing['text_tokens']['cached']['input_per_million']
    assert_equal 0.5, pricing['text_tokens']['cached']['output_per_million']
  end

  def test_build_pricing_with_defaults
    model = {}  # No prices provided
    pricing = @provider.send(:build_pricing, model)
    assert_equal 1.0, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 5.0, pricing['text_tokens']['standard']['output_per_million']
  end

  def test_build_pricing_without_cache_prices_provided
    model = { input_price: 2.0, output_price: 4.0 }
    pricing = @provider.send(:build_pricing, model)
    assert_equal 2.0, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 4.0, pricing['text_tokens']['standard']['output_per_million']
    # Code calculates default cache prices
    assert_equal 2.5, pricing['text_tokens']['cached']['input_per_million']
    assert_equal 0.4, pricing['text_tokens']['cached']['output_per_million']
  end

  def test_build_pricing_with_zero_cache_write_price
    model = { input_price: 2.0, output_price: 4.0, cache_write_price: 0.0 }
    pricing = @provider.send(:build_pricing, model)
    refute pricing['text_tokens']['cached']
  end

  def test_build_pricing_with_negative_cache_write_price
    model = { input_price: 2.0, output_price: 4.0, cache_write_price: -1.0 }
    pricing = @provider.send(:build_pricing, model)
    refute pricing['text_tokens']['cached']
  end

  def test_build_pricing_calculates_cache_write_price_from_input
    model = { input_price: 2.0, output_price: 4.0, cache_write_price: nil, cache_hit_price: 0.5 }
    pricing = @provider.send(:build_pricing, model)
    assert_equal 2.5, pricing['text_tokens']['cached']['input_per_million']  # 2.0 * 1.25
    assert_equal 0.5, pricing['text_tokens']['cached']['output_per_million']
  end

  def test_build_pricing_uses_calculated_cache_hit_price_when_not_provided
    model = { input_price: 2.0, output_price: 4.0, cache_write_price: 3.0, cache_hit_price: nil }
    pricing = @provider.send(:build_pricing, model)
    assert_equal 0.4, pricing['text_tokens']['cached']['output_per_million']  # output_price * 0.1
  end

  def test_extract_family_gpt_models
    assert_equal 'gpt', @provider.send(:extract_family, 'gpt-5')
    assert_equal 'gpt', @provider.send(:extract_family, 'gpt-4')
    assert_equal 'gpt', @provider.send(:extract_family, 'gpt-3')
  end

  def test_extract_family_claude_models
    assert_equal 'claude-sonnet-4', @provider.send(:extract_family, 'claude-sonnet-4-5')
    assert_equal 'claude-3-5', @provider.send(:extract_family, 'claude-3-5-haiku')
    assert_equal 'claude-opus-4', @provider.send(:extract_family, 'claude-opus-4-1')
  end

  def test_extract_family_qwen3_coder
    assert_equal 'qwen3', @provider.send(:extract_family, 'qwen3-coder')
  end

  def test_extract_family_grok_code
    assert_equal 'grok', @provider.send(:extract_family, 'grok-code')
  end

  def test_extract_family_kimi_k2
    assert_equal 'kimi', @provider.send(:extract_family, 'kimi-k2')
  end

  def test_extract_family_unknown_model
    assert_equal 'unknown', @provider.send(:extract_family, 'unknown-model-name')
    assert_equal 'some', @provider.send(:extract_family, 'some-other-model')
  end

  def test_extract_family_empty_string
    assert_nil @provider.send(:extract_family, '')
  end

  def test_extract_family_single_word
    assert_equal 'single', @provider.send(:extract_family, 'single')
  end

  def test_save_models_to_jsonl_creates_directory_and_file
    models = [
      { 'name' => 'Model 1', 'id' => 'model-1' },
      { 'name' => 'Model 2', 'id' => 'model-2' }
    ]

    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/opencode-zen')
        assert File.exist?('catalog/opencode-zen/models.jsonl')

        content = File.read('catalog/opencode-zen/models.jsonl')
        lines = content.strip.split("\n")
        assert_equal 2, lines.size

        parsed_models = lines.map { |line| JSON.parse(line) }
        assert_equal 'Model 1', parsed_models[0]['name']
        assert_equal 'Model 2', parsed_models[1]['name']
      end
    end
  end

  def test_save_models_to_jsonl_with_empty_models
    models = []

    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/opencode-zen')
        assert File.exist?('catalog/opencode-zen/models.jsonl')

        content = File.read('catalog/opencode-zen/models.jsonl')
        assert_equal '', content.strip  # Empty file
      end
    end
  end

  def test_run_handles_process_models_exception
    @provider.stub :process_models, -> { raise StandardError.new('Process error') } do
      assert_raises StandardError do
        @provider.run
      end
    end
  end
end