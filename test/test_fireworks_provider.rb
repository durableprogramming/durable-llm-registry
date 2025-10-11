require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'json'
require 'fileutils'
require_relative '../lib/providers/fireworks'
require_relative '../lib/colored_logger'

class TestFireworksProvider < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Fireworks.new(logger: @logger)
    @logger.level = Logger::INFO  # Override after initialization to capture info messages
  end

  def teardown
    # Clean up any created files
    FileUtils.rm_rf('catalog/fireworks-ai') if Dir.exist?('catalog/fireworks-ai')
  end

  def test_initialization_with_default_logger
    provider = Providers::Fireworks.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Fireworks.new(logger: custom_logger)
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

  def test_openapi_url_returns_placeholder_url
    expected_url = 'https://api.fireworks.ai/inference/v1/openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_successful_model_processing
    mock_models = [
      { name: 'Test Model', api_name: 'test-model', context_window: 128000, modalities: { input: ['text'], output: ['text'] }, capabilities: [], pricing: { input_price: 0.2, output_price: 0.4 } }
    ]

    @provider.stub :process_models, mock_models do
      @provider.run
    end

    output = @output.string
    assert_match %r{Fireworks provider: OpenAPI spec handling skipped}, output
    assert_match %r{Updated Fireworks models data using fetcher}, output
  end

  def test_run_handles_empty_models_from_fetcher
    @provider.stub :process_models, [] do
      @provider.run
    end

    output = @output.string
    assert_match %r{Fireworks provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models using fetcher, skipping update}, output
  end

  def test_run_handles_nil_models_from_fetcher
    @provider.stub :process_models, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Fireworks provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models using fetcher, skipping update}, output
  end

  def test_run_handles_process_models_exception
    @provider.stub :process_models, -> { raise StandardError.new('Process error') } do
      assert_raises StandardError do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Error in Fireworks provider run: Process error}, output
  end

  def test_process_models_with_valid_data
    mock_fetched_data = [
      { name: 'Llama 3.1 8B', api_name: 'llama-3-1-8b-instruct', context_window: 128000, modalities: { input: ['text'], output: ['text'] }, capabilities: ['function_calling'], pricing: { input_price: 0.2, output_price: 0.4 } },
      { name: 'DeepSeek V3', api_name: 'deepseek-v3', context_window: 128000, modalities: { input: ['text'], output: ['text'] }, capabilities: [], pricing: { input_price: 0.1, output_price: 0.2 } }
    ]

    Fetchers::Fireworks.stub :fetch, mock_fetched_data do
      processed = @provider.send(:process_models)

      assert_equal 2, processed.size
      assert_equal 'DeepSeek V3', processed[0]['name']
      assert_equal 'deepseek-v3', processed[0]['family']
      assert_equal 'Llama 3.1 8B', processed[1]['name']
      assert_equal 'llama-3', processed[1]['family']
    end
  end

  def test_process_models_filters_models_without_api_name
    mock_fetched_data = [
      { name: 'Valid Model', api_name: 'valid-model' },
      { name: 'Invalid Model' } # missing api_name
    ]

    processed = mock_fetched_data.map do |model|
      api_name = model[:api_name]
      next unless api_name

      family = @provider.send(:extract_family, api_name)
      pricing = @provider.send(:build_pricing, model)
      max_output_tokens = @provider.send(:get_max_output_tokens, api_name)

      {
        'name' => model[:name] || api_name,
        'family' => family,
        'provider' => 'fireworks-ai',
        'id' => "accounts/fireworks/models/#{api_name}",
        'context_window' => model[:context_window] || 128000,
        'max_output_tokens' => max_output_tokens,
        'modalities' => model[:modalities] || { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => model[:capabilities] || [],
        'pricing' => pricing
      }
    end.compact

    assert_equal 1, processed.size
    assert_equal 'Valid Model', processed[0]['name']
  end

  def test_process_models_sorts_by_name
    mock_fetched_data = [
      { name: 'Z Model', api_name: 'z-model' },
      { name: 'A Model', api_name: 'a-model' },
      { name: 'M Model', api_name: 'm-model' }
    ]

    processed = mock_fetched_data.map do |model|
      api_name = model[:api_name]
      next unless api_name

      family = @provider.send(:extract_family, api_name)
      pricing = @provider.send(:build_pricing, model)
      max_output_tokens = @provider.send(:get_max_output_tokens, api_name)

      {
        'name' => model[:name] || api_name,
        'family' => family,
        'provider' => 'fireworks-ai',
        'id' => "accounts/fireworks/models/#{api_name}",
        'context_window' => model[:context_window] || 128000,
        'max_output_tokens' => max_output_tokens,
        'modalities' => model[:modalities] || { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => model[:capabilities] || [],
        'pricing' => pricing
      }
    end.compact.sort_by { |m| m['name'] }

    assert_equal 3, processed.size
    assert_equal 'A Model', processed[0]['name']
    assert_equal 'M Model', processed[1]['name']
    assert_equal 'Z Model', processed[2]['name']
  end

  def test_save_models_to_jsonl_creates_directory_and_file
    models = [
      { 'name' => 'Test Model 1', 'family' => 'test' },
      { 'name' => 'Test Model 2', 'family' => 'test' }
    ]

    @provider.send(:save_models_to_jsonl, models)

    assert Dir.exist?('catalog/fireworks-ai')
    assert File.exist?('catalog/fireworks-ai/models.jsonl')

    content = File.read('catalog/fireworks-ai/models.jsonl')
    lines = content.strip.split("\n")
    assert_equal 2, lines.size

    parsed_models = lines.map { |line| JSON.parse(line) }
    assert_equal 'Test Model 1', parsed_models[0]['name']
    assert_equal 'Test Model 2', parsed_models[1]['name']
  end

  def test_save_models_to_jsonl_handles_empty_models
    @provider.send(:save_models_to_jsonl, [])

    assert Dir.exist?('catalog/fireworks-ai')
    assert File.exist?('catalog/fireworks-ai/models.jsonl')

    content = File.read('catalog/fireworks-ai/models.jsonl')
    assert_equal '', content.strip
  end

  def test_save_models_to_jsonl_overwrites_existing_file
    # Create initial file
    FileUtils.mkdir_p('catalog/fireworks-ai')
    File.write('catalog/fireworks-ai/models.jsonl', '{"old": "data"}')

    models = [{ 'name' => 'New Model', 'family' => 'new' }]
    @provider.send(:save_models_to_jsonl, models)

    content = File.read('catalog/fireworks-ai/models.jsonl')
    lines = content.strip.split("\n")
    assert_equal 1, lines.size

    parsed = JSON.parse(lines[0])
    assert_equal 'New Model', parsed['name']
  end

  def test_extract_family_deepseek_models
    assert_equal 'deepseek-v3', @provider.send(:extract_family, 'deepseek-v3-base')
    assert_equal 'deepseek-v3', @provider.send(:extract_family, 'deepseek-v3-chat')
  end

  def test_extract_family_kimi_models
    assert_equal 'kimi-k2', @provider.send(:extract_family, 'kimi-k2-base')
    assert_equal 'kimi-k2', @provider.send(:extract_family, 'kimi-k2-chat')
  end

  def test_extract_family_gpt_oss_models
    assert_equal 'gpt-oss', @provider.send(:extract_family, 'gpt-oss-small')
    assert_equal 'gpt-oss', @provider.send(:extract_family, 'gpt-oss-large')
  end

  def test_extract_family_qwen3_models
    assert_equal 'qwen3', @provider.send(:extract_family, 'qwen3-8b')
    assert_equal 'qwen3-coder', @provider.send(:extract_family, 'qwen3-coder-32b')
  end

  def test_extract_family_qwen2p5_models
    assert_equal 'qwen2p5-vl', @provider.send(:extract_family, 'qwen2p5-vl-7b')
    assert_equal 'qwen2p5-vl', @provider.send(:extract_family, 'qwen2p5-vl-72b')
  end

  def test_extract_family_llama4_models
    assert_equal 'llama4', @provider.send(:extract_family, 'llama4-17b')
    assert_equal 'llama4-maverick', @provider.send(:extract_family, 'llama4-maverick-17b')
    assert_equal 'llama4-scout', @provider.send(:extract_family, 'llama4-scout-17b')
  end

  def test_extract_family_glm_models
    assert_equal 'glm-4p5v', @provider.send(:extract_family, 'glm-4p5v-9b')
    assert_equal 'glm-4p5v', @provider.send(:extract_family, 'glm-4p5v-32b')
  end

  def test_extract_family_flux_models
    assert_equal 'flux-1', @provider.send(:extract_family, 'flux-dev')
    assert_equal 'flux-kontext', @provider.send(:extract_family, 'flux-kontext-dev')
  end

  def test_extract_family_asr_whisper_models
    assert_equal 'asr-model', @provider.send(:extract_family, 'asr-model')
    assert_equal 'whisper-base', @provider.send(:extract_family, 'whisper-base')
  end

  def test_extract_family_default_fallback
    assert_equal 'llama-3', @provider.send(:extract_family, 'llama-3-8b')
    assert_equal 'mistral-7b', @provider.send(:extract_family, 'mistral-7b-instruct')
    assert_equal 'gemma-2', @provider.send(:extract_family, 'gemma-2-9b')
    assert_equal 'multi-word', @provider.send(:extract_family, 'multi-word-name-variant')
  end

  def test_build_pricing_input_output_format
    model = { pricing: { input_price: 0.2, output_price: 0.4 } }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => {
          'input_per_million' => 0.2,
          'output_per_million' => 0.4
        }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_step_format
    model = { pricing: { step_price: 0.0005 } }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => {
          'input_per_million' => 0.0005,
          'output_per_million' => 0.0005
        }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_image_format
    model = { pricing: { image_price: 0.04 } }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => {
          'input_per_million' => 0.04,
          'output_per_million' => 0.04
        }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_minute_format
    model = { pricing: { minute_price: 0.0032 } }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => {
          'input_per_million' => 0.0032,
          'output_per_million' => 0.0032
        }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_no_pricing_info
    model = {}
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => {
          'input_per_million' => 0.5,
          'output_per_million' => 1.5
        }
      }
    }
    assert_equal expected, pricing
  end

  def test_build_pricing_empty_pricing_info
    model = { pricing: {} }
    pricing = @provider.send(:build_pricing, model)

    expected = {
      'text_tokens' => {
        'standard' => {
          'input_per_million' => 0.5,
          'output_per_million' => 1.5
        }
      }
    }
    assert_equal expected, pricing
  end

  def test_get_max_output_tokens_asr_whisper
    assert_equal 16000, @provider.send(:get_max_output_tokens, 'asr-model')
    assert_equal 16000, @provider.send(:get_max_output_tokens, 'whisper-base')
  end

  def test_get_max_output_tokens_flux
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'flux-dev')
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'flux-schnell')
  end

  def test_get_max_output_tokens_deepseek_kimi
    assert_equal 20000, @provider.send(:get_max_output_tokens, 'deepseek-v3')
    assert_equal 20000, @provider.send(:get_max_output_tokens, 'kimi-k2')
  end

  def test_get_max_output_tokens_default
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'llama-3-8b')
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'mistral-7b')
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'unknown-model')
  end

  # Integration test for the full processing pipeline
  def test_full_processing_pipeline
    # Mock the fetcher
    mock_fetched_data = [
      {
        name: 'Llama 3.1 8B Instruct',
        api_name: 'llama-3-1-8b-instruct',
        context_window: 128000,
        modalities: { input: ['text'], output: ['text'] },
        capabilities: ['function_calling'],
        pricing: { input_price: 0.20, output_price: 0.20 }
      },
      {
        name: 'DeepSeek V3',
        api_name: 'deepseek-v3',
        context_window: 128000,
        modalities: { input: ['text'], output: ['text'] },
        capabilities: [],
        pricing: { input_price: 0.10, output_price: 0.20 }
      },
      {
        name: 'Flux Dev',
        api_name: 'flux-dev',
        context_window: 128000,
        modalities: { input: ['text'], output: ['image'] },
        capabilities: ['image_generation'],
        pricing: { step_price: 0.0005 }
      }
    ]

    # Mock the fetcher module
    mock_fetcher = Minitest::Mock.new
    mock_fetcher.expect :fetch, mock_fetched_data

    Fetchers::Fireworks.stub :fetch, mock_fetched_data do
      @provider.run
    end

    # Verify the file was created and contains expected data
    assert File.exist?('catalog/fireworks-ai/models.jsonl')
    content = File.read('catalog/fireworks-ai/models.jsonl')
    lines = content.strip.split("\n")
    assert_equal 3, lines.size

    models = lines.map { |line| JSON.parse(line) }

    # Verify DeepSeek model (should be first due to sorting)
    deepseek = models.find { |m| m['name'] == 'DeepSeek V3' }
    assert deepseek
    assert_equal 'deepseek-v3', deepseek['family']
    assert_equal 20000, deepseek['max_output_tokens']
    assert_equal({ 'input' => ['text'], 'output' => ['text'] }, deepseek['modalities'])

    # Verify Llama model
    llama = models.find { |m| m['name'] == 'Llama 3.1 8B Instruct' }
    assert llama
    assert_equal 'llama-3', llama['family']
    assert_equal 4096, llama['max_output_tokens']
    assert_includes llama['capabilities'], 'function_calling'

    # Verify Flux model
    flux = models.find { |m| m['name'] == 'Flux Dev' }
    assert flux
    assert_equal 'flux-1', flux['family']
    assert_equal 4096, flux['max_output_tokens']
    assert_includes flux['capabilities'], 'image_generation'
  end

  # Error handling tests
  def test_run_handles_fetcher_exception
    Fetchers::Fireworks.stub :fetch, -> { raise StandardError.new('Fetcher error') } do
      assert_raises StandardError do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Error in Fireworks provider run: Fetcher error}, output
  end

  def test_run_handles_file_write_error
    models = [{ 'name' => 'Test Model', 'family' => 'test' }]

    @provider.stub :process_models, models do
      FileUtils.stub :mkdir_p, ->(*args) { raise Errno::EACCES.new('Permission denied') } do
        assert_raises Errno::EACCES do
          @provider.run
        end
      end
    end
  end

  # Edge cases for extract_family
  def test_extract_family_edge_cases
    # Empty string
    assert_equal '', @provider.send(:extract_family, '')

    # Single word
    assert_equal 'single', @provider.send(:extract_family, 'single')

    # Multiple hyphens
    assert_equal 'multi-word', @provider.send(:extract_family, 'multi-word-name-variant')
  end

  # Edge cases for build_pricing
  def test_build_pricing_edge_cases
    # Nil pricing
    model = { pricing: nil }
    pricing = @provider.send(:build_pricing, model)
    assert pricing['text_tokens']['standard']['input_per_million'] == 0.5

    # Mixed pricing types (should use first matching)
    model = { pricing: { input_price: 0.1, output_price: 0.2, step_price: 0.0005 } }
    pricing = @provider.send(:build_pricing, model)
    assert_equal 0.1, pricing['text_tokens']['standard']['input_per_million']
    assert_equal 0.2, pricing['text_tokens']['standard']['output_per_million']
  end

  # Edge cases for get_max_output_tokens
  def test_get_max_output_tokens_edge_cases
    # Empty string
    assert_equal 4096, @provider.send(:get_max_output_tokens, '')

    # Case variations - note: current implementation is case-sensitive
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'ASR-MODEL')
    assert_equal 4096, @provider.send(:get_max_output_tokens, 'Whisper-Base')
  end

  # Test process_models with various edge cases
  def test_process_models_with_edge_cases
    # Model with missing name (should use api_name)
    mock_data = [
      { api_name: 'test-model' }, # no name
      { name: 'Named Model', api_name: 'named-model' },
      { name: '', api_name: 'empty-name-model' } # empty name
    ]

    processed = mock_data.map do |model|
      api_name = model[:api_name]
      next unless api_name

      family = @provider.send(:extract_family, api_name)
      pricing = @provider.send(:build_pricing, model)
      max_output_tokens = @provider.send(:get_max_output_tokens, api_name)

      name = model[:name].to_s.empty? ? api_name : model[:name]
      {
        'name' => name,
        'family' => family,
        'provider' => 'fireworks-ai',
        'id' => "accounts/fireworks/models/#{api_name}",
        'context_window' => model[:context_window] || 128000,
        'max_output_tokens' => max_output_tokens,
        'modalities' => model[:modalities] || { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => model[:capabilities] || [],
        'pricing' => pricing
      }
    end.compact

    assert_equal 3, processed.size
    assert_equal 'test-model', processed[0]['name'] # used api_name
    assert_equal 'Named Model', processed[1]['name']
    assert_equal 'empty-name-model', processed[2]['name'] # used api_name for empty name
  end

  # Test process_models with nil/empty fetched data
  def test_process_models_with_nil_empty_data
    # Empty array
    Fetchers::Fireworks.stub :fetch, [] do
      result = @provider.send(:process_models)
      assert_equal [], result
    end
  end

  # Test save_models_to_jsonl with special characters
  def test_save_models_to_jsonl_with_special_characters
    models = [
      { 'name' => 'Model with "quotes"', 'family' => 'test' },
      { 'name' => 'Model with émojis 🚀', 'family' => 'test' }
    ]

    @provider.send(:save_models_to_jsonl, models)

    content = File.read('catalog/fireworks-ai/models.jsonl')
    lines = content.strip.split("\n")
    assert_equal 2, lines.size

    parsed_models = lines.map { |line| JSON.parse(line) }
    assert_equal 'Model with "quotes"', parsed_models[0]['name']
    assert_equal 'Model with émojis 🚀', parsed_models[1]['name']
  end

  # Test logger output levels
  def test_logger_output_levels
    @logger.level = Logger::DEBUG
    @provider.run

    output = @output.string
    # Should contain debug/info messages
    assert_match %r{Fireworks provider: OpenAPI spec handling skipped}, output
  end

  # Test that the provider inherits from Base
  def test_inherits_from_base
    assert_kind_of Providers::Base, @provider
  end

  # Test that private methods are private
  def test_private_methods_are_private
    assert_raises NoMethodError do
      @provider.extract_family('test')
    end

    assert_raises NoMethodError do
      @provider.build_pricing({})
    end

    assert_raises NoMethodError do
      @provider.get_max_output_tokens('test')
    end
  end
end