require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require 'yaml'
require_relative '../lib/providers/openai'
require_relative '../lib/colored_logger'

class TestOpenai < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @provider = Providers::Openai.new(logger: @logger)
  end

  def test_initialization_with_default_logger
    provider = Providers::Openai.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Openai.new(logger: custom_logger)
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
    expected_url = 'https://raw.githubusercontent.com/api-evangelist/openai/main/openapi/chat-openapi-original.yml'
    assert_equal expected_url, @provider.openapi_url
  end

  def test_run_successful_download_and_save
    mock_spec_content = "openapi: 3.0.0\ninfo:\n  title: OpenAI API\n"

    @provider.stub :download_openapi_spec, mock_spec_content do
      @provider.stub :save_spec_to_catalog, nil do
        @provider.run
      end
    end

    output = @output.string
    assert_match %r{Downloading OpenAI OpenAPI spec}, output
    assert_match %r{Updated OpenAI OpenAPI spec}, output
  end

  def test_run_handles_download_failure
    @provider.stub :download_openapi_spec, nil do
      @provider.run
    end

    output = @output.string
    assert_match %r{Downloading OpenAI OpenAPI spec}, output
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
end