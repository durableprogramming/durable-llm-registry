require 'json'
require 'open3'
require 'timeout'
require_relative '../colored_logger'

module Fetchers
  class OpencodeCli
    COMMAND = %w[npx -y opencode-ai@latest models --verbose].freeze
    TIMEOUT = 120

    class FetchError < StandardError; end

    attr_reader :logger

    def initialize(logger: ColoredLogger.new(STDOUT))
      @logger = logger
      @logger.level = Logger::WARN
    end

    def self.fetch(**options)
      new(**options).fetch
    end

    # Returns a hash of { "provider_id" => [model_hash, ...] }
    def fetch
      output = run_command
      return {} if output.nil? || output.strip.empty?

      models_by_provider = parse_output(output)
      logger.info("Fetched #{models_by_provider.values.sum(&:size)} models across #{models_by_provider.size} providers")
      models_by_provider
    rescue => e
      logger.error("Failed to fetch opencode CLI data: #{e.class} - #{e.message}")
      {}
    end

    private

    HEADER_LINE = /\A(\S+)\/(\S+)\z/

    def run_command
      stdout, stderr, status = Timeout.timeout(TIMEOUT) { Open3.capture3(*COMMAND) }
      unless status.success?
        raise FetchError, "opencode CLI exited with status #{status.exitstatus}: #{stderr}"
      end
      stdout
    rescue Errno::ENOENT => e
      raise FetchError, "opencode CLI not found: #{e.message}"
    rescue Timeout::Error
      raise FetchError, "opencode CLI timed out after #{TIMEOUT}s"
    end

    def parse_output(output)
      models_by_provider = Hash.new { |h, k| h[k] = [] }
      header = nil
      buffer = []
      depth = 0

      output.each_line do |line|
        stripped = line.strip
        if buffer.empty? && depth.zero? && stripped =~ HEADER_LINE
          header = stripped
          next
        end

        next if header.nil?

        buffer << line
        depth += stripped.count('{') - stripped.count('}')

        if depth.zero? && !buffer.empty?
          begin
            json = JSON.parse(buffer.join)
            provider_id = header.split('/', 2).first
            models_by_provider[provider_id] << json
          rescue JSON::ParserError => e
            logger.warn("Error parsing opencode CLI JSON block for #{header}: #{e.message}")
          end
          header = nil
          buffer = []
        end
      end

      models_by_provider
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
