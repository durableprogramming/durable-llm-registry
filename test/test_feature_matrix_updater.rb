require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require_relative '../lib/feature_matrix_updater'

class TestFeatureMatrixUpdater < Minitest::Test
  def setup
    @output = StringIO.new
    $stdout = @output
  end

  def teardown
    $stdout = STDOUT
  end

  def test_generate_feature_matrix_with_mocked_providers
    mock_providers = [
      mock_provider_class('TestProvider1', true, false, true),
      mock_provider_class('TestProvider2', false, true, false)
    ]

    expected_matrix = [
      { provider: 'TestProvider1', api_specs: true, model_info: false, pricing: true },
      { provider: 'TestProvider2', api_specs: false, model_info: true, pricing: false }
    ]

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, mock_providers
    begin
      matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix
      assert_equal expected_matrix, matrix
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_feature_matrix_handles_provider_initialization_errors
    mock_provider_class = Class.new do
      def self.name
        'TestProvider'
      end

      def can_pull_api_specs?
        true
      end

      def can_pull_model_info?
        true
      end

      def can_pull_pricing?
        true
      end
    end

    mock_provider_class.define_singleton_method(:new) do
      raise StandardError.new('Init error')
    end

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, [mock_provider_class]
    begin
      assert_raises(StandardError) do
        Providers::FeatureMatrixUpdater.generate_feature_matrix
      end
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_feature_matrix_handles_method_errors
    mock_provider_class = Class.new do
      def self.name
        'TestProvider'
      end

      def can_pull_api_specs?
        raise StandardError.new('API specs error')
      end

      def can_pull_model_info?
        true
      end

      def can_pull_pricing?
        true
      end
    end

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, [mock_provider_class]
    begin
      assert_raises(StandardError) do
        Providers::FeatureMatrixUpdater.generate_feature_matrix
      end
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_markdown_with_sample_matrix
    sample_matrix = [
      { provider: 'Provider1', api_specs: true, model_info: false, pricing: true },
      { provider: 'Provider2', api_specs: false, model_info: true, pricing: false }
    ]

    expected_markdown = "# Provider Feature Matrix\n\nThis matrix shows which providers support dynamic pulling of API specifications, model information, and pricing data.\n\n| Provider | API Specs | Model Info | Pricing |\n|----------|-----------|------------|---------|\n| Provider1 | ✅ | ❌ | ✅ |\n| Provider2 | ❌ | ✅ | ❌ |\n"

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert_equal expected_markdown, markdown
    end
  end

  def test_generate_markdown_handles_empty_matrix
    empty_matrix = []

    expected_markdown = "# Provider Feature Matrix\n\nThis matrix shows which providers support dynamic pulling of API specifications, model information, and pricing data.\n\n| Provider | API Specs | Model Info | Pricing |\n|----------|-----------|------------|---------|\n"

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, empty_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert_equal expected_markdown, markdown
    end
  end

  def test_update_feature_matrix_file_writes_to_file
    sample_markdown = "# Sample Markdown\n"

    File.stub :write, nil do
      Providers::FeatureMatrixUpdater.stub :generate_markdown, sample_markdown do
        Providers::FeatureMatrixUpdater.update_feature_matrix_file
      end
    end

    assert_match %r{Updated FEATURE_MATRIX.md}, @output.string
  end

  def test_update_feature_matrix_file_handles_write_error
    sample_markdown = "# Sample Markdown\n"

    File.stub :write, ->(*) { raise StandardError.new('Write error') } do
      Providers::FeatureMatrixUpdater.stub :generate_markdown, sample_markdown do
        assert_raises(StandardError) do
          Providers::FeatureMatrixUpdater.update_feature_matrix_file
        end
      end
    end
  end

  def test_providers_constant_includes_expected_providers
    expected_providers = [
      Providers::Anthropic,
      Providers::AzureOpenai,
      Providers::Cohere,
      Providers::Deepseek,
      Providers::Fireworks,
      Providers::Google,
      Providers::Groq,
      Providers::Mistral,
      Providers::Openai,
      Providers::Opencode,
      Providers::OpenRouter,
      Providers::Perplexity,
      Providers::Together,
      Providers::XAI
    ]

    assert_equal expected_providers, Providers::FeatureMatrixUpdater::PROVIDERS
  end

  def test_generate_feature_matrix_with_real_providers
    # This test uses real providers, assuming they are properly implemented
    matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix

    assert_kind_of Array, matrix
    refute_empty matrix

    matrix.each do |row|
      assert_includes row.keys, :provider
      assert_includes row.keys, :api_specs
      assert_includes row.keys, :model_info
      assert_includes row.keys, :pricing

      assert_kind_of String, row[:provider]
      assert_includes [true, false], row[:api_specs]
      assert_includes [true, false], row[:model_info]
      assert_includes [true, false], row[:pricing]
    end
  end

  def test_generate_markdown_with_real_data
    markdown = Providers::FeatureMatrixUpdater.generate_markdown

    assert_kind_of String, markdown
    assert_match %r{# Provider Feature Matrix}, markdown
    assert_match %r{| Provider | API Specs | Model Info | Pricing |}, markdown
    assert_match %r{|----------|-----------|------------|---------|}, markdown
    assert_match %r{✅|❌}, markdown  # Should contain checkmarks or crosses
  end

  def test_generate_feature_matrix_provider_name_without_module
    mock_provider_class = Class.new do
      def self.name
        'TestProvider'
      end

      def can_pull_api_specs?
        true
      end

      def can_pull_model_info?
        false
      end

      def can_pull_pricing?
        true
      end
    end

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, [mock_provider_class]
    begin
      matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix
      assert_equal [{ provider: 'TestProvider', api_specs: true, model_info: false, pricing: true }], matrix
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_feature_matrix_with_provider_methods_returning_non_boolean
    mock_provider_class = Class.new do
      def self.name
        'Providers::TestProvider'
      end

      def can_pull_api_specs?
        'yes'
      end

      def can_pull_model_info?
        nil
      end

      def can_pull_pricing?
        1
      end
    end

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, [mock_provider_class]
    begin
      matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix
      expected = [{ provider: 'TestProvider', api_specs: 'yes', model_info: nil, pricing: 1 }]
      assert_equal expected, matrix
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_markdown_with_special_characters_in_provider_names
    sample_matrix = [
      { provider: 'Provider-1', api_specs: true, model_info: false, pricing: true },
      { provider: 'Provider_2', api_specs: false, model_info: true, pricing: false },
      { provider: 'Provider (3)', api_specs: true, model_info: true, pricing: true }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert_match %r{\| Provider-1 \| ✅ \| ❌ \| ✅ \|}, markdown
      assert_match %r{\| Provider_2 \| ❌ \| ✅ \| ❌ \|}, markdown
      assert_match %r{\| Provider \(3\) \| ✅ \| ✅ \| ✅ \|}, markdown
    end
  end

  def test_generate_markdown_all_false
    sample_matrix = [
      { provider: 'Provider1', api_specs: false, model_info: false, pricing: false }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert_match %r{\| Provider1 \| ❌ \| ❌ \| ❌ \|}, markdown
    end
  end

  def test_generate_markdown_all_true
    sample_matrix = [
      { provider: 'Provider1', api_specs: true, model_info: true, pricing: true }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert_match %r{\| Provider1 \| ✅ \| ✅ \| ✅ \|}, markdown
    end
  end

  def test_update_feature_matrix_file_calls_file_write_with_correct_arguments
    sample_markdown = "# Test Markdown\n"

    mock_file_write = Minitest::Mock.new
    mock_file_write.expect :call, nil, ['FEATURE_MATRIX.md', sample_markdown]

    File.stub :write, mock_file_write do
      Providers::FeatureMatrixUpdater.stub :generate_markdown, sample_markdown do
        Providers::FeatureMatrixUpdater.update_feature_matrix_file
      end
    end

    mock_file_write.verify
  end

  def test_update_feature_matrix_file_outputs_correct_message
    sample_markdown = "# Test Markdown\n"

    File.stub :write, nil do
      Providers::FeatureMatrixUpdater.stub :generate_markdown, sample_markdown do
        Providers::FeatureMatrixUpdater.update_feature_matrix_file
      end
    end

    assert_equal "Updated FEATURE_MATRIX.md\n", @output.string
  end

  def test_generate_markdown_includes_header_and_description
    sample_matrix = [
      { provider: 'Provider1', api_specs: true, model_info: false, pricing: true }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert_match %r{^# Provider Feature Matrix\n\n}, markdown
      assert_match %r{This matrix shows which providers support dynamic pulling of API specifications, model information, and pricing data.\n\n}, markdown
    end
  end

  def test_generate_markdown_table_structure
    sample_matrix = [
      { provider: 'Provider1', api_specs: true, model_info: false, pricing: true },
      { provider: 'Provider2', api_specs: false, model_info: true, pricing: false }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      lines = markdown.split("\n")
      assert_equal "| Provider | API Specs | Model Info | Pricing |", lines[4]
      assert_equal "|----------|-----------|------------|---------|", lines[5]
      assert_equal "| Provider1 | ✅ | ❌ | ✅ |", lines[6]
      assert_equal "| Provider2 | ❌ | ✅ | ❌ |", lines[7]
    end
  end

  def test_generate_feature_matrix_returns_correct_structure
    mock_providers = [mock_provider_class('TestProvider', true, false, true)]

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, mock_providers
    begin
      matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix
      assert_kind_of Array, matrix
      assert_equal 1, matrix.size
      row = matrix.first
      assert_kind_of Hash, row
      assert_equal [:provider, :api_specs, :model_info, :pricing].sort, row.keys.sort
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_providers_constant_is_array_of_classes
    assert_kind_of Array, Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater::PROVIDERS.each do |provider|
      assert_kind_of Class, provider
    end
  end

  def test_generate_feature_matrix_with_multiple_providers_order_preserved
    mock_providers = [
      mock_provider_class('First', true, false, true),
      mock_provider_class('Second', false, true, false),
      mock_provider_class('Third', true, true, true)
    ]

    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, mock_providers
    begin
      matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix
      assert_equal ['First', 'Second', 'Third'], matrix.map { |r| r[:provider] }
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_markdown_ends_with_newline
    sample_matrix = [
      { provider: 'Provider1', api_specs: true, model_info: false, pricing: true }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      assert markdown.end_with?("\n")
    end
  end

  def test_update_feature_matrix_file_handles_generate_markdown_error
    Providers::FeatureMatrixUpdater.stub :generate_markdown, -> { raise StandardError.new('Markdown error') } do
      assert_raises(StandardError) do
        Providers::FeatureMatrixUpdater.update_feature_matrix_file
      end
    end
  end

  def test_generate_feature_matrix_with_empty_providers_list
    original = Providers::FeatureMatrixUpdater::PROVIDERS
    Providers::FeatureMatrixUpdater.const_set :PROVIDERS, []
    begin
      matrix = Providers::FeatureMatrixUpdater.generate_feature_matrix
      assert_equal [], matrix
    ensure
      Providers::FeatureMatrixUpdater.const_set :PROVIDERS, original
    end
  end

  def test_generate_markdown_with_matrix_having_nil_values
    sample_matrix = [
      { provider: 'Provider1', api_specs: nil, model_info: nil, pricing: nil }
    ]

    Providers::FeatureMatrixUpdater.stub :generate_feature_matrix, sample_matrix do
      markdown = Providers::FeatureMatrixUpdater.generate_markdown
      # nil is falsy, so should show ❌
      assert_match %r{\| Provider1 \| ❌ \| ❌ \| ❌ \|}, markdown
    end
  end

  private

  def mock_provider_class(name, api_specs, model_info, pricing)
    Class.new do
      define_singleton_method(:name) do
        "Providers::#{name}"
      end

      define_method(:can_pull_api_specs?) do
        api_specs
      end

      define_method(:can_pull_model_info?) do
        model_info
      end

      define_method(:can_pull_pricing?) do
        pricing
      end
    end
  end
end