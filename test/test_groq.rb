require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/groq'
require_relative '../lib/colored_logger'

class TestGroq < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Groq.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Groq.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Groq.new(logger: custom_logger)
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
    expected_url = 'https://api.groq.com/openai/v1/openapi.yaml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_handles_api_fetch_failure
    @provider.stub :fetch_models_from_api, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Groq provider: OpenAPI spec handling skipped}, output
    assert_match %r{Failed to fetch models from Groq API}, output
  end

  def test_run_successful_api_fetch_and_save
    mock_models_data = [
      { 'id' => 'llama-3.1-8b-instant', 'context_window' => 131072, 'max_tokens' => 131072 }
    ]
    mock_processed_models = [
      {
        'name' => 'llama-3.1-8b-instant',
        'family' => 'llama-3.1-8b',
        'provider' => 'groq',
        'id' => 'llama-3.1-8b-instant',
        'context_window' => 131072,
        'max_output_tokens' => 131072,
        'modalities' => { 'input' => ['text'], 'output' => ['text'] },
        'capabilities' => [],
        'pricing' => {
          'text_tokens' => {
            'standard' => { 'input_per_million' => 0.05, 'output_per_million' => 0.08 }
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
    assert_match %r{Groq provider: OpenAPI spec handling skipped}, output
    assert_match %r{Updated Groq models data from API}, output
  end

  def test_fetch_models_from_api_success
    mock_response = '{"data": [{"id": "test-model", "context_window": 128000}]}'
    Net::HTTP.stub :get, mock_response do
      result = @provider.send(:fetch_models_from_api)
      assert_equal [{"id" => "test-model", "context_window" => 128000}], result
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
      { 'id' => 'llama-3.1-8b-instant', 'context_window' => 131072, 'max_tokens' => 131072 }
    ]
    result = @provider.send(:process_models_from_api, mock_data)
    assert_kind_of Array, result
    assert_equal 1, result.size
    model = result.first
    assert_equal 'llama-3.1-8b-instant', model['name']
    assert_equal 'llama-3.1-8b', model['family']
    assert_equal 'groq', model['provider']
  end

  def test_process_models_from_api_with_empty_data
    result = @provider.send(:process_models_from_api, [])
    assert_empty result
  end

  def test_process_models_from_api_with_nil_values
    mock_data = [
      { 'id' => 'test-model', 'context_window' => nil, 'max_output_tokens' => nil }
    ]
    result = @provider.send(:process_models_from_api, mock_data)
    model = result.first
    refute model.key?('context_window')
    refute model.key?('max_output_tokens')
  end

  def test_process_models_from_api_with_missing_keys
    mock_data = [
      { 'id' => 'test-model' } # missing context_window and max_output_tokens
    ]
    result = @provider.send(:process_models_from_api, mock_data)
    model = result.first
    refute model.key?('context_window')
    refute model.key?('max_output_tokens')
  end

  def test_process_models_from_api_sorts_by_name
    mock_data = [
      { 'id' => 'z-model', 'context_window' => 1000, 'max_output_tokens' => 1000 },
      { 'id' => 'a-model', 'context_window' => 1000, 'max_output_tokens' => 1000 }
    ]
    result = @provider.send(:process_models_from_api, mock_data)
    assert_equal 'a-model', result.first['name']
    assert_equal 'z-model', result.last['name']
  end

  def test_process_models_from_api_compacts_nil_values
    mock_data = [
      { 'id' => 'test-model', 'context_window' => nil, 'max_output_tokens' => 1000, 'some_nil_field' => nil }
    ]
    result = @provider.send(:process_models_from_api, mock_data)
    model = result.first
    refute model.key?('context_window'), "nil context_window should be compacted"
    refute model.key?('some_nil_field'), "nil some_nil_field should be compacted"
    assert model.key?('max_output_tokens'), "non-nil max_output_tokens should be present"
  end

  def test_process_models_returns_correct_structure
    models = @provider.send(:process_models, nil)
    assert_kind_of Array, models
    assert models.size > 0

    model_ids = models.map { |m| m['id'] }
    assert_includes model_ids, 'llama-3.1-8b-instant'
    assert_includes model_ids, 'llama-3.3-70b-versatile'

    model = models.find { |m| m['id'] == 'llama-3.1-8b-instant' }
    assert_equal 'Llama 3.1 8B Instant', model['name']
    assert_equal 'llama-3.1-8b', model['family']
    assert_equal 'groq', model['provider']
    assert_equal 131072, model['context_window']
    assert_equal 131072, model['max_output_tokens']
    assert_equal ['text'], model['modalities']['input']
    assert_equal ['text'], model['modalities']['output']
    assert_equal ['function_calling'], model['capabilities']
    assert model['pricing']['text_tokens']['standard']['input_per_million'] > 0
  end

  def test_process_models_specific_model_validations
    models = @provider.send(:process_models, nil)

    # Test whisper model (audio input)
    whisper = models.find { |m| m['id'] == 'whisper-large-v3' }
    assert_equal ['audio'], whisper['modalities']['input']
    assert_equal ['text'], whisper['modalities']['output']
    assert_equal ['speech_to_text'], whisper['capabilities']
    assert_nil whisper['pricing']

    # Test compound model
    compound = models.find { |m| m['id'] == 'groq/compound' }
    assert_equal ['web_search', 'code_execution', 'tool_use'], compound['capabilities']
    assert_nil compound['pricing']

    # Test TTS model
    tts = models.find { |m| m['id'] == 'playai-tts' }
    assert_equal ['text'], tts['modalities']['input']
    assert_equal ['audio'], tts['modalities']['output']
    assert_equal ['text_to_speech'], tts['capabilities']
    assert_nil tts['pricing']
  end

  def test_process_models_total_count
    models = @provider.send(:process_models, nil)
    # Based on the hardcoded list in groq.rb, there should be 15 models
    assert_equal 15, models.size
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
      # pricing may be nil
      # context_window and max_output_tokens may be nil for audio models
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
        assert pricing['input_per_million'] > 0, "Non-positive input price for #{model['id']}"
      end
      if pricing['output_per_million']
        assert pricing['output_per_million'] > 0, "Non-positive output price for #{model['id']}"
      end
    end
  end

  def test_process_models_all_models_have_valid_modalities
    models = @provider.send(:process_models, nil)
    valid_modalities = ['text', 'image', 'audio']

    models.each do |model|
      model['modalities']['input'].each do |mod|
        assert_includes valid_modalities, mod, "Invalid input modality #{mod} for #{model['id']}"
      end
      model['modalities']['output'].each do |mod|
        assert_includes valid_modalities, mod, "Invalid output modality #{mod} for #{model['id']}"
      end
    end
  end

  def test_process_models_modalities_combinations
    models = @provider.send(:process_models, nil)

    text_to_text_models = models.select { |m| m['modalities']['input'] == ['text'] && m['modalities']['output'] == ['text'] }
    assert text_to_text_models.size > 0, "Should have text-to-text models"

    audio_to_text_models = models.select { |m| m['modalities']['input'] == ['audio'] && m['modalities']['output'] == ['text'] }
    assert audio_to_text_models.size > 0, "Should have audio-to-text models"

    text_to_audio_models = models.select { |m| m['modalities']['input'] == ['text'] && m['modalities']['output'] == ['audio'] }
    assert text_to_audio_models.size > 0, "Should have text-to-audio models"
  end

  def test_process_models_is_sorted_by_name
    models = @provider.send(:process_models, nil)
    names = models.map { |m| m['name'] }
    assert_equal names.sort, names
  end

  def test_extract_family_for_known_models
    test_cases = {
      'llama-3.1-8b-instant' => 'llama-3.1-8b',
      'llama-3.3-70b-versatile' => 'llama-3.3-70b',
      'meta-llama/llama-guard-4-12b' => 'llama-guard',
      'openai/gpt-oss-120b' => 'gpt-oss-120b',
      'openai/gpt-oss-20b' => 'gpt-oss-20b',
      'whisper-large-v3' => 'whisper',
      'whisper-large-v3-turbo' => 'whisper',
      'groq/compound' => 'groq-compound',
      'groq/compound-mini' => 'groq-compound',
      'codestral-2508' => 'codestral-2508',
      'pixtral-large-2411' => 'pixtral-large',
      'mistral-medium-2508' => 'mistral-medium',
      'meta-llama/llama-4-maverick-17b-128e-instruct' => 'llama-4',
      'moonshotai/kimi-k2-instruct-0905' => 'kimi-k2',
      'qwen/qwen3-32b' => 'qwen3-32b',
      'playai-tts' => 'playai-tts',
      'playai-tts-arabic' => 'playai-tts'
    }

    test_cases.each do |model_id, expected_family|
      assert_equal expected_family, @provider.send(:extract_family, model_id), "Failed for #{model_id}"
    end
  end

  def test_extract_family_fallback_patterns
    test_cases = {
      'unknown-model' => 'unknown-model',
      'single-word' => 'single-word',
      'two-words-here' => 'two-words',
      'three-word-model-name' => 'three-word',
      'namespace/model' => 'model',
      'deep/nested/path/model' => 'model'
    }

    test_cases.each do |model_id, expected_family|
      assert_equal expected_family, @provider.send(:extract_family, model_id), "Failed for #{model_id}"
    end
  end

  def test_get_pricing_for_model_known_models
    test_cases = {
      'llama-3.1-8b-instant' => { input: 0.05, output: 0.08 },
      'llama-3.3-70b-versatile' => { input: 0.59, output: 0.79 },
      'meta-llama/llama-guard-4-12b' => { input: 0.20, output: 0.20 },
      'openai/gpt-oss-120b' => { input: 0.15, output: 0.75 },
      'openai/gpt-oss-20b' => { input: 0.10, output: 0.50 },
      'meta-llama/llama-4-maverick-17b-128e-instruct' => { input: 0.20, output: 0.60 },
      'meta-llama/llama-4-scout-17b-16e-instruct' => { input: 0.11, output: 0.34 },
      'moonshotai/kimi-k2-instruct-0905' => { input: 1.00, output: 3.00 },
      'qwen/qwen3-32b' => { input: 0.29, output: 0.59 }
    }

    test_cases.each do |model_id, expected_pricing|
      pricing = @provider.send(:get_pricing_for_model, model_id)
      expected = {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => expected_pricing[:input],
            'output_per_million' => expected_pricing[:output]
          }
        }
      }
      assert_equal expected, pricing, "Failed for #{model_id}"
    end
  end

  def test_get_pricing_for_model_nil_pricing_models
    nil_pricing_models = [
      'whisper-large-v3',
      'whisper-large-v3-turbo',
      'groq/compound',
      'groq/compound-mini',
      'playai-tts',
      'playai-tts-arabic'
    ]

    nil_pricing_models.each do |model_id|
      pricing = @provider.send(:get_pricing_for_model, model_id)
      assert_nil pricing, "Expected nil pricing for #{model_id}"
    end
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
        assert Dir.exist?('catalog/groq')
        assert File.exist?('catalog/groq/models.jsonl')
        content = File.read('catalog/groq/models.jsonl')
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
        assert Dir.exist?('catalog/groq')
        assert File.exist?('catalog/groq/models.jsonl')
        content = File.read('catalog/groq/models.jsonl')
        assert_equal "\n", content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_models_to_jsonl_handles_file_write_errors
    models = [{ 'id' => 'test' }]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        # Make catalog directory read-only to simulate write error
        FileUtils.mkdir_p('catalog')
        FileUtils.chmod(0444, 'catalog')

        assert_raises(Errno::EACCES) do
          @provider.send(:save_models_to_jsonl, models)
        end
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_models_to_jsonl_creates_parent_directories
    models = [{ 'id' => 'test' }]

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        # Ensure parent directory doesn't exist
        refute Dir.exist?('catalog')

        @provider.send(:save_models_to_jsonl, models)
        assert Dir.exist?('catalog/groq')
        assert File.exist?('catalog/groq/models.jsonl')
      ensure
        Dir.chdir(original_dir)
      end
    end
  end
end