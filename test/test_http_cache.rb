require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'tempfile'
require 'json'
require_relative '../lib/http_cache'
require_relative '../lib/colored_logger'

class TestHttpCache < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
    @logger.level = Logger::INFO
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @temp_dir if Dir.exist?(@temp_dir)
  end

  def test_initialize_with_valid_cache_dir
    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    assert cache.instance_variable_get(:@cache_enabled)
    assert_match %r{Cache enabled at}, @output.string
  end

  def test_initialize_with_nil_cache_dir
    cache = HttpCache.new(cache_dir: nil, logger: @logger)
    refute cache.instance_variable_get(:@cache_enabled)
    assert_match %r{Cache disabled}, @output.string
  end

  def test_initialize_with_non_writable_cache_dir
    non_writable_dir = File.join(@temp_dir, 'non_writable')
    Dir.mkdir(non_writable_dir)
    FileUtils.chmod(0444, non_writable_dir)  # Read only

    cache = HttpCache.new(cache_dir: non_writable_dir, logger: @logger)
    refute cache.instance_variable_get(:@cache_enabled)
    assert_match %r{Cache directory not writable}, @output.string

    FileUtils.chmod(0755, non_writable_dir)  # Restore permissions for cleanup
  end

  def test_initialize_with_faraday_options
    options = { timeout: 10, open_timeout: 5 }
    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger, **options)
    assert_equal options, cache.instance_variable_get(:@faraday_options)
  end

  def test_get_cache_hit
    url = 'http://example.com'
    cache_key = Digest::MD5.hexdigest(url)
    cache_file = File.join(@temp_dir, cache_key)
    cached_data = {
      'timestamp' => (Time.now - 60).to_s,  # Fresh
      'response' => {
        'body' => 'cached body',
        'status' => 200,
        'headers' => { 'content-type' => 'text/plain' }
      }
    }
    File.write(cache_file, JSON.generate(cached_data))

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    response = cache.get(url)

    assert_equal 'cached body', response.body
    assert_equal 200, response.status
    assert response.success?
    assert_match %r{Cache hit for}, @output.string
  end

  def test_get_cache_stale
    url = 'http://example.com'
    cache_key = Digest::MD5.hexdigest(url)
    cache_file = File.join(@temp_dir, cache_key)
    cached_data = {
      'timestamp' => (Time.now - 400).to_s,  # Stale
      'response' => {
        'body' => 'stale body',
        'status' => 200,
        'headers' => {}
      }
    }
    File.write(cache_file, JSON.generate(cached_data))

    mock_response = mock()
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns('fresh body')
    mock_response.stubs(:status).returns(200)
    mock_response.stubs(:headers).returns({ 'content-type' => 'text/plain' })

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'fresh body', response.body
      assert_equal 200, response.status
      assert_match %r{Cache stale for}, @output.string
      assert_match %r{Making request to}, @output.string
      assert_match %r{Caching response for}, @output.string
    end
  end

  def test_get_cache_miss
    url = 'http://example.com'

    mock_response = mock()
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns('new body')
    mock_response.stubs(:status).returns(200)
    mock_response.stubs(:headers).returns({})

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'new body', response.body
      assert_equal 200, response.status
      assert_match %r{Cache miss for}, @output.string
      assert_match %r{Making request to}, @output.string
      assert_match %r{Caching response for}, @output.string
    end
  end

  def test_get_failed_request_not_cached
    url = 'http://example.com'

    mock_response = mock()
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:body).returns('error body')
    mock_response.stubs(:status).returns(404)
    mock_response.stubs(:headers).returns({})

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'error body', response.body
      assert_equal 404, response.status
      refute response.success?
      assert_match %r{Cache miss for}, @output.string
      assert_match %r{Making request to}, @output.string
      refute_match %r{Caching response for}, @output.string
    end
  end

  def test_get_with_cache_disabled
    url = 'http://example.com'

    mock_response = Minitest::Mock.new
    mock_response.expect(:success?, true)
    mock_response.expect(:body, 'body')
    mock_response.expect(:status, 200)
    mock_response.expect(:headers, {})

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: nil, logger: @logger)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'body', response.body
      assert_match %r{Cache disabled}, @output.string
      refute_match %r{Cache hit|Cache miss}, @output.string
    end
  end

  def test_get_handles_corrupted_cache_file
    url = 'http://example.com'
    cache_key = Digest::MD5.hexdigest(url)
    cache_file = File.join(@temp_dir, cache_key)
    File.write(cache_file, 'invalid json')

    mock_response = mock()
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns('body')
    mock_response.stubs(:status).returns(200)
    mock_response.stubs(:headers).returns({})

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'body', response.body
      assert_match %r{Cache stale for}, @output.string
    end
  end

  def test_get_handles_invalid_timestamp_in_cache
    url = 'http://example.com'
    cache_key = Digest::MD5.hexdigest(url)
    cache_file = File.join(@temp_dir, cache_key)
    cached_data = {
      'timestamp' => 'invalid timestamp',
      'response' => {
        'body' => 'body',
        'status' => 200,
        'headers' => {}
      }
    }
    File.write(cache_file, JSON.generate(cached_data))

    mock_response = mock()
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns('fresh body')
    mock_response.stubs(:status).returns(200)
    mock_response.stubs(:headers).returns({})

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'fresh body', response.body
      assert_match %r{Cache stale for}, @output.string  # Treated as stale due to invalid timestamp
    end
  end

  def test_get_handles_caching_failure
    url = 'http://example.com'

    mock_response = mock()
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:body).returns('body')
    mock_response.stubs(:status).returns(200)
    mock_response.stubs(:headers).returns({})

    mock_connection = Minitest::Mock.new
    mock_connection.expect(:get, mock_response, [url])

    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    # Make cache dir non-writable to simulate caching failure
    FileUtils.chmod(0444, @temp_dir)
    cache.stub :faraday_connection, mock_connection do
      response = cache.get(url)

      assert_equal 'body', response.body
      assert_match %r{Making request to}, @output.string
      # Should not crash even if caching fails
    end
    FileUtils.chmod(0755, @temp_dir)  # Restore for cleanup
  end

  def test_faraday_connection_initialization
    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger, timeout: 10)
    connection = cache.send(:faraday_connection)
    assert_kind_of Faraday::Connection, connection
    # Second call should return the same instance
    assert_same connection, cache.send(:faraday_connection)
  end

  def test_create_response_from_cache_data
    response_data = {
      'body' => 'test body',
      'status' => 200,
      'headers' => { 'content-type' => 'application/json' }
    }
    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    response = cache.send(:create_response, response_data)

    assert_equal 'test body', response.body
    assert_equal 200, response.status
    assert_equal({ 'content-type' => 'application/json' }, response.headers)
    assert response.success?
  end

  def test_create_response_with_missing_headers
    response_data = {
      'body' => 'test body',
      'status' => 200
    }
    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)
    response = cache.send(:create_response, response_data)

    assert_equal({}, response.headers)
  end

  def test_create_response_success_check
    cache = HttpCache.new(cache_dir: @temp_dir, logger: @logger)

    success_response = cache.send(:create_response, { 'status' => 200 })
    assert success_response.success?

    error_response = cache.send(:create_response, { 'status' => 404 })
    refute error_response.success?

    no_status_response = cache.send(:create_response, {})
    refute no_status_response.success?
  end

  def test_constants
    assert_equal 300, HttpCache::CACHE_DURATION
  end
end