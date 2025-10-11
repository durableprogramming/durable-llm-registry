 require 'faraday'
 require 'json'
 require 'fileutils'
 require 'digest/md5'
 require 'ostruct'
 require_relative 'colored_logger'

class HttpCache
  CACHE_DURATION = 300 # 5 minutes in seconds

  def initialize(cache_dir: '.cache', logger: ColoredLogger.new(STDOUT), **faraday_options)
    @cache_dir = cache_dir
    @logger = logger
    @faraday_options = faraday_options
    @cache_enabled = setup_cache_dir
    @logger.warn("Cache disabled") unless @cache_enabled
  end

  def get(url)
    if @cache_enabled
      cache_key = Digest::MD5.hexdigest(url)
      cache_file = File.join(@cache_dir, cache_key)

      if File.exist?(cache_file)
        cached_data = load_cache(cache_file)
        if cached_data && fresh?(cached_data['timestamp'])
          @logger.info("Cache hit for #{url}")
          return create_response(cached_data['response'])
        else
          @logger.info("Cache stale for #{url}")
        end
      else
        @logger.info("Cache miss for #{url}")
      end
    end

    # Make the request
    @logger.info("Making request to #{url}")
    response = faraday_connection.get(url)

    # Cache successful responses
    if @cache_enabled && response.success?
      @logger.info("Caching response for #{url}")
      cache_response(cache_file, response)
    end

    response
  end

  private

  def setup_cache_dir
    return false unless @cache_dir

    begin
      FileUtils.mkdir_p(@cache_dir) unless Dir.exist?(@cache_dir)
      if File.writable?(@cache_dir)
        @logger.info("Cache enabled at #{@cache_dir}")
        true
      else
        @logger.warn("Cache directory not writable: #{@cache_dir}")
        false
      end
    rescue => e
      @logger.error("Failed to setup cache directory: #{e.message}")
      false
    end
  end

  def faraday_connection
    @connection ||= Faraday.new do |conn|
      @faraday_options.each do |key, value|
        conn.options.send("#{key}=", value)
      end
      conn.adapter Faraday.default_adapter
    end
  end

  def load_cache(cache_file)
    JSON.parse(File.read(cache_file))
  rescue
    nil
  end

  def fresh?(timestamp_str)
    Time.now - Time.parse(timestamp_str) < CACHE_DURATION
  rescue
    false
  end

  def create_response(response_data)
    OpenStruct.new(
      body: response_data['body'],
      status: response_data['status'],
      headers: response_data['headers'] || {},
      success?: response_data['status'] && response_data['status'] >= 200 && response_data['status'] < 300
    )
  end

  def cache_response(cache_file, response)
    cache_data = {
      'timestamp' => Time.now.to_s,
      'response' => {
        'body' => response.body,
        'status' => response.status,
        'headers' => response.headers.to_h
      }
    }

    File.write(cache_file, JSON.generate(cache_data))
  rescue
    # Silently fail if caching fails
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.