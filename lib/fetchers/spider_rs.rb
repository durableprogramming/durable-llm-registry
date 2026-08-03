require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class SpiderRs
    GENERATED_RS_URL = 'https://raw.githubusercontent.com/spider-rs/llm_models/main/src/generated.rs'
    TIMEOUT = 30

    class FetchError < StandardError; end

    attr_reader :logger

    def initialize(logger: ColoredLogger.new(STDOUT))
      @logger = logger
      @logger.level = Logger::WARN
    end

    def self.fetch(**options)
      new(**options).fetch
    end

    ENTRY_LINE = /
      ModelInfoEntry\s*\{\s*
      name:\s*"(?<name>[^"]*)",\s*
      supports_vision:\s*(?<vision>true|false),\s*
      supports_audio:\s*(?<audio>true|false),\s*
      supports_video:\s*(?<video>true|false),\s*
      supports_pdf:\s*(?<pdf>true|false),\s*
      max_input_tokens:\s*(?<max_input>\d+),\s*
      max_output_tokens:\s*(?<max_output>\d+),\s*
      cost_input_x1000:\s*(?<cost_input>\d+),\s*
      cost_output_x1000:\s*(?<cost_output>\d+),\s*
      arena_overall:\s*(?<arena>\d+)\s*
      \}
    /x

    # Returns an array of model hashes (flat, no provider grouping is available upstream)
    def fetch
      body = fetch_source
      return [] if body.nil? || body.strip.empty?

      models = parse_entries(body)
      logger.info("Fetched #{models.size} models from spider-rs/llm_models")
      models
    rescue => e
      logger.error("Failed to fetch spider-rs llm_models data: #{e.class} - #{e.message}")
      []
    end

    private

    def fetch_source
      response = connection.get(GENERATED_RS_URL)
      unless response.success?
        raise FetchError, "HTTP #{response.status} fetching generated.rs"
      end
      response.body
    rescue Faraday::Error => e
      logger.error("Failed to fetch generated.rs: #{e.message}")
      nil
    end

    def connection
      @connection ||= HttpCache.new(timeout: TIMEOUT, open_timeout: TIMEOUT / 2)
    end

    def parse_entries(body)
      body.to_enum(:scan, ENTRY_LINE).map do
        m = Regexp.last_match
        {
          name: m[:name],
          supports_vision: m[:vision] == 'true',
          supports_audio: m[:audio] == 'true',
          supports_video: m[:video] == 'true',
          supports_pdf: m[:pdf] == 'true',
          max_input_tokens: m[:max_input].to_i,
          max_output_tokens: m[:max_output].to_i,
          input_cost_per_million: m[:cost_input].to_f / 1000.0,
          output_cost_per_million: m[:cost_output].to_f / 1000.0,
          arena_score: m[:arena].to_i / 100.0
        }
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
