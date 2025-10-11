require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'net/http'
require 'fileutils'
require_relative '../lib/providers/base'
require_relative '../lib/colored_logger'
require_relative '../lib/openapi/validator'

class TestBase < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
  end

  def test_initialization_with_default_logger
    provider = Providers::Base.new
    assert_kind_of ColoredLogger, provider.instance_variable_get(:@logger)
  end

  def test_initialization_with_custom_logger
    custom_logger = Logger.new(STDOUT)
    provider = Providers::Base.new(logger: custom_logger)
    assert_equal custom_logger, provider.instance_variable_get(:@logger)
  end

  def test_run_raises_not_implemented_error
    provider = Providers::Base.new(logger: @logger)
    assert_raises NotImplementedError do
      provider.run
    end
  end

  def test_download_openapi_spec_successful
    provider = Providers::Base.new(logger: @logger)
    mock_response = "openapi: 3.0.0\ninfo:\n  title: Test API\n"

    Net::HTTP.stub :get, mock_response do
      result = provider.send(:download_openapi_spec, 'https://example.com/spec.yaml')
      assert_equal mock_response, result
    end
  end

  def test_download_openapi_spec_with_invalid_url
    provider = Providers::Base.new(logger: @logger)

    Net::HTTP.stub :get, ->(uri) { raise SocketError.new('getaddrinfo: Name or service not known') } do
      assert_raises SocketError do
        provider.send(:download_openapi_spec, 'https://invalid-url-that-does-not-exist.com/spec.yaml')
      end
    end
  end

  def test_download_openapi_spec_with_http_error
    provider = Providers::Base.new(logger: @logger)

    Net::HTTP.stub :get, ->(uri) { raise Net::HTTPServerException.new('404 Not Found', nil) } do
      assert_raises Net::HTTPServerException do
        provider.send(:download_openapi_spec, 'https://example.com/nonexistent.yaml')
      end
    end
  end

  def test_download_openapi_spec_with_empty_response
    provider = Providers::Base.new(logger: @logger)

    Net::HTTP.stub :get, '' do
      result = provider.send(:download_openapi_spec, 'https://example.com/empty.yaml')
      assert_equal '', result
    end
  end

  def test_download_openapi_spec_with_large_response
    provider = Providers::Base.new(logger: @logger)
    large_content = 'x' * 1000000  # 1MB of content

    Net::HTTP.stub :get, large_content do
      result = provider.send(:download_openapi_spec, 'https://example.com/large.yaml')
      assert_equal large_content, result
      assert_equal 1000000, result.length
    end
  end

  def test_download_openapi_spec_with_special_characters
    provider = Providers::Base.new(logger: @logger)
    content_with_special_chars = "openapi: 3.0.0\ninfo:\n  title: API with spécial chärs 🚀\n  description: \"Test with quotes\"\n"

    Net::HTTP.stub :get, content_with_special_chars do
      result = provider.send(:download_openapi_spec, 'https://example.com/special.yaml')
      assert_equal content_with_special_chars, result
    end
  end

  def test_validate_spec_valid_spec
    provider = Providers::Base.new(logger: @logger)
    valid_spec_content = "openapi: 3.0.0\ninfo:\n  title: Valid API\npaths: {}\n"

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [valid_spec_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [true, []] do
        valid, errors = provider.send(:validate_spec, valid_spec_content)
        assert valid
        assert_empty errors
      end
    end

    mock_tempfile.verify
  end

  def test_validate_spec_invalid_spec
    provider = Providers::Base.new(logger: @logger)
    invalid_spec_content = "invalid: yaml: content: [\n"

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [invalid_spec_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [false, ['Invalid YAML syntax']] do
        valid, errors = provider.send(:validate_spec, invalid_spec_content)
        refute valid
        assert_equal ['Invalid YAML syntax'], errors
      end
    end

    mock_tempfile.verify
  end

  def test_validate_spec_validation_error
    provider = Providers::Base.new(logger: @logger)
    spec_content = "openapi: 3.0.0\ninfo:\n  title: API\n"

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [spec_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [false, ['Missing required field: paths']] do
        valid, errors = provider.send(:validate_spec, spec_content)
        refute valid
        assert_equal ['Missing required field: paths'], errors
      end
    end

    mock_tempfile.verify
  end

  def test_validate_spec_tempfile_creation_failure
    provider = Providers::Base.new(logger: @logger)

    Tempfile.stub :new, ->(*args) { raise Errno::ENOSPC.new } do
      assert_raises Errno::ENOSPC do
        provider.send(:validate_spec, 'content')
      end
    end
  end

  def test_validate_spec_validator_raises_error
    provider = Providers::Base.new(logger: @logger)
    spec_content = "openapi: 3.0.0\n"

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [spec_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    # unlink is not called when validator raises error

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, -> { raise StandardError.new('Validator crashed') } do
        assert_raises StandardError do
          provider.send(:validate_spec, spec_content)
        end
      end
    end

    mock_tempfile.verify
  end

  def test_validate_spec_empty_content
    provider = Providers::Base.new(logger: @logger)

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, ['']
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [false, ['Empty content']] do
        valid, errors = provider.send(:validate_spec, '')
        refute valid
        assert_equal ['Empty content'], errors
      end
    end

    mock_tempfile.verify
  end

  def test_validate_spec_large_content
    provider = Providers::Base.new(logger: @logger)
    large_content = 'x' * 1000000

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [large_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [true, []] do
        valid, errors = provider.send(:validate_spec, large_content)
        assert valid
        assert_empty errors
      end
    end

    mock_tempfile.verify
  end

  def test_save_spec_to_catalog_creates_directory_and_file
    provider = Providers::Base.new(logger: @logger)
    spec_content = "openapi: 3.0.0\ninfo:\n  title: Test API\n"
    provider_name = 'test_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, spec_content)

        assert Dir.exist?('catalog/test_provider')
        assert File.exist?('catalog/test_provider/openapi.yaml')
        content = File.read('catalog/test_provider/openapi.yaml')
        assert_equal spec_content, content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_with_existing_directory
    provider = Providers::Base.new(logger: @logger)
    spec_content = "openapi: 3.0.0\n"
    provider_name = 'existing_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        FileUtils.mkdir_p('catalog/existing_provider')
        File.write('catalog/existing_provider/openapi.yaml', 'old content')

        provider.send(:save_spec_to_catalog, provider_name, spec_content)

        content = File.read('catalog/existing_provider/openapi.yaml')
        assert_equal spec_content, content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_with_nested_directories
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"
    provider_name = 'deep/nested/provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, spec_content)

        assert Dir.exist?('catalog/deep/nested/provider')
        assert File.exist?('catalog/deep/nested/provider/openapi.yaml')
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_with_empty_content
    provider = Providers::Base.new(logger: @logger)
    provider_name = 'empty_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, '')

        assert Dir.exist?('catalog/empty_provider')
        content = File.read('catalog/empty_provider/openapi.yaml')
        assert_equal '', content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_with_special_characters_in_name
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"
    provider_name = 'special-provider_name'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, spec_content)

        assert Dir.exist?('catalog/special-provider_name')
        assert File.exist?('catalog/special-provider_name/openapi.yaml')
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_file_write_failure
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"
    provider_name = 'failing_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        # Make the directory read-only to cause write failure
        FileUtils.mkdir_p('catalog/failing_provider')
        FileUtils.chmod(0444, 'catalog/failing_provider')

        assert_raises Errno::EACCES do
          provider.send(:save_spec_to_catalog, provider_name, spec_content)
        end
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_directory_creation_failure
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"
    provider_name = 'fail_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        # Make the catalog directory read-only
        FileUtils.mkdir_p('catalog')
        FileUtils.chmod(0444, 'catalog')

        assert_raises Errno::EACCES do
          provider.send(:save_spec_to_catalog, provider_name, spec_content)
        end
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_save_spec_to_catalog_overwrites_existing_file
    provider = Providers::Base.new(logger: @logger)
    old_content = "old openapi spec"
    new_content = "new openapi spec"
    provider_name = 'overwrite_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)
        FileUtils.mkdir_p('catalog/overwrite_provider')
        File.write('catalog/overwrite_provider/openapi.yaml', old_content)

        provider.send(:save_spec_to_catalog, provider_name, new_content)

        content = File.read('catalog/overwrite_provider/openapi.yaml')
        assert_equal new_content, content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_download_openapi_spec_handles_uri_parsing
    provider = Providers::Base.new(logger: @logger)
    url = 'https://example.com/path/to/spec.yaml?query=1'

    Net::HTTP.stub :get, 'response' do
      result = provider.send(:download_openapi_spec, url)
      assert_equal 'response', result
    end
  end

  def test_validate_spec_handles_nil_content
    provider = Providers::Base.new(logger: @logger)

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [nil]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [false, ['Nil content']] do
        valid, errors = provider.send(:validate_spec, nil)
        refute valid
        assert_equal ['Nil content'], errors
      end
    end

    mock_tempfile.verify
  end

  def test_save_spec_to_catalog_handles_nil_content
    provider = Providers::Base.new(logger: @logger)
    provider_name = 'nil_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, nil)

        content = File.read('catalog/nil_provider/openapi.yaml')
        assert_equal '', content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_download_openapi_spec_with_timeout_simulation
    provider = Providers::Base.new(logger: @logger)

    Net::HTTP.stub :get, ->(uri) { raise Net::ReadTimeout.new('Read timeout') } do
      assert_raises Net::ReadTimeout do
        provider.send(:download_openapi_spec, 'https://slow-server.com/spec.yaml')
      end
    end
  end

  def test_validate_spec_with_binary_content
    provider = Providers::Base.new(logger: @logger)
    binary_content = "\x00\x01\x02\x03binary data"

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [binary_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [false, ['Binary content not valid YAML']] do
        valid, errors = provider.send(:validate_spec, binary_content)
        refute valid
        assert_equal ['Binary content not valid YAML'], errors
      end
    end

    mock_tempfile.verify
  end

  def test_save_spec_to_catalog_with_unicode_content
    provider = Providers::Base.new(logger: @logger)
    unicode_content = "openapi: 3.0.0\ninfo:\n  title: API with Unicode 🚀\n  description: 测试\n"
    provider_name = 'unicode_provider'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, unicode_content)

        content = File.read('catalog/unicode_provider/openapi.yaml', encoding: 'UTF-8')
        assert_equal unicode_content, content
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_initialization_with_nil_logger
    provider = Providers::Base.new(logger: nil)
    assert_nil provider.instance_variable_get(:@logger)
  end

  def test_download_openapi_spec_with_malformed_url
    provider = Providers::Base.new(logger: @logger)

    URI.stub :parse, ->(url) { raise URI::InvalidURIError.new('bad URI') } do
      assert_raises URI::InvalidURIError do
        provider.send(:download_openapi_spec, 'not-a-url')
      end
    end
  end

  def test_validate_spec_tempfile_unlink_failure
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, [spec_content]
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil do
      raise Errno::ENOENT.new
    end

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [true, []] do
        # Should raise error if unlink fails
        assert_raises Errno::ENOENT do
          provider.send(:validate_spec, spec_content)
        end
      end
    end

    mock_tempfile.verify
  end

  def test_save_spec_to_catalog_with_relative_path_provider_name
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"
    provider_name = '../outside_catalog'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        # This should still work as FileUtils.mkdir_p handles relative paths
        provider.send(:save_spec_to_catalog, provider_name, spec_content)

        # catalog/../outside_catalog resolves to outside_catalog
        assert Dir.exist?('outside_catalog')
        assert File.exist?('outside_catalog/openapi.yaml')
      ensure
        Dir.chdir(original_dir)
      end
    end
  end

  def test_run_method_not_overridden_in_subclass
    # Test that a subclass that doesn't override run still raises NotImplementedError
    subclass = Class.new(Providers::Base) do
      # Don't override run
    end

    instance = subclass.new(logger: @logger)
    assert_raises NotImplementedError do
      instance.run
    end
  end

  def test_private_methods_are_private
    provider = Providers::Base.new(logger: @logger)

    # These should raise NoMethodError when called publicly
    assert_raises NoMethodError do
      provider.download_openapi_spec('url')
    end

    assert_raises NoMethodError do
      provider.validate_spec('content')
    end

    assert_raises NoMethodError do
      provider.save_spec_to_catalog('name', 'content')
    end
  end

  def test_download_openapi_spec_returns_string
    provider = Providers::Base.new(logger: @logger)

    Net::HTTP.stub :get, 'response content' do
      result = provider.send(:download_openapi_spec, 'https://example.com/spec.yaml')
      assert_kind_of String, result
    end
  end

  def test_validate_spec_returns_array
    provider = Providers::Base.new(logger: @logger)

    mock_tempfile = Minitest::Mock.new
    mock_tempfile.expect :write, nil, ['content']
    mock_tempfile.expect :close, nil
    mock_tempfile.expect :path, '/tmp/test.yaml'
    mock_tempfile.expect :unlink, nil

    Tempfile.stub :new, mock_tempfile do
      OpenAPI::Validator.stub :validate, [true, ['error1', 'error2']] do
        valid, errors = provider.send(:validate_spec, 'content')
        assert_kind_of Array, [valid, errors]
        assert_equal 2, [valid, errors].size
        assert_kind_of TrueClass, valid
        assert_kind_of Array, errors
      end
    end

    mock_tempfile.verify
  end

  def test_save_spec_to_catalog_creates_correct_file_path
    provider = Providers::Base.new(logger: @logger)
    spec_content = "content"
    provider_name = 'test'

    Dir.mktmpdir do |tmpdir|
      original_dir = Dir.pwd
      begin
        Dir.chdir(tmpdir)

        provider.send(:save_spec_to_catalog, provider_name, spec_content)

        expected_path = File.join('catalog', 'test', 'openapi.yaml')
        assert File.exist?(expected_path)
      ensure
        Dir.chdir(original_dir)
      end
    end
  end
end