require 'yaml'
require 'open3'
require 'timeout'
require 'tmpdir'
require_relative '../colored_logger'

module Fetchers
  class Truefoundry
    REPO_URL = 'https://github.com/truefoundry/models.git'
    CLONE_TIMEOUT = 120

    class FetchError < StandardError; end

    attr_reader :logger

    def initialize(logger: ColoredLogger.new(STDOUT))
      @logger = logger
      @logger.level = Logger::WARN
    end

    def self.fetch(**options)
      new(**options).fetch
    end

    # Returns a hash of { "provider_name" => [ { model:, upstream_vendor:, data: {..raw merged yaml..} }, ... ] }
    def fetch
      Dir.mktmpdir do |dir|
        clone_repo(dir)
        return parse_providers(File.join(dir, 'providers'))
      end
    rescue => e
      logger.error("Failed to fetch truefoundry/models data: #{e.class} - #{e.message}")
      {}
    end

    private

    def clone_repo(dest)
      _stdout, stderr, status = Timeout.timeout(CLONE_TIMEOUT) do
        Open3.capture3('git', 'clone', '--depth', '1', REPO_URL, dest)
      end
      raise FetchError, "git clone failed: #{stderr}" unless status.success?
    rescue Errno::ENOENT => e
      raise FetchError, "git not found: #{e.message}"
    rescue Timeout::Error
      raise FetchError, "git clone timed out after #{CLONE_TIMEOUT}s"
    end

    def parse_providers(providers_dir)
      return {} unless Dir.exist?(providers_dir)

      result = {}

      Dir.glob("#{providers_dir}/*").select { |d| File.directory?(d) }.each do |provider_dir|
        provider_name = File.basename(provider_dir)
        default_data = load_default(provider_dir)
        models = parse_provider_models(provider_dir, provider_name, default_data)
        result[provider_name] = models unless models.empty?
      end

      logger.info("Fetched #{result.values.sum(&:size)} models across #{result.size} providers from truefoundry/models")
      result
    end

    def load_default(provider_dir)
      default_path = File.join(provider_dir, 'default.yaml')
      return {} unless File.exist?(default_path)

      YAML.load_file(default_path) || {}
    rescue Psych::SyntaxError => e
      logger.warn("Error parsing #{default_path}: #{e.message}")
      {}
    end

    def parse_provider_models(provider_dir, provider_name, default_data)
      models = []

      Dir.glob("#{provider_dir}/**/*.yaml").each do |path|
        next if File.basename(path) == 'default.yaml'

        begin
          data = YAML.load_file(path)
          next unless data

          merged = default_data.merge(data)
          upstream_vendor = extract_upstream_vendor(provider_dir, provider_name, path)

          models << { data: merged, upstream_vendor: upstream_vendor }
        rescue Psych::SyntaxError => e
          logger.warn("Error parsing #{path}: #{e.message}")
        end
      end

      models
    end

    # Only meaningful for the `openrouter` provider, where truefoundry nests
    # models under providers/openrouter/<org>/<model>.yaml. OpenRouter's price
    # is its own markup/passthrough, not the org's direct API price, so the
    # org is tracked separately rather than relabeling the provider.
    def extract_upstream_vendor(provider_dir, provider_name, path)
      return nil unless provider_name == 'openrouter'

      relative = path.delete_prefix("#{provider_dir}/")
      parts = relative.split('/')
      parts.size > 1 ? parts.first : nil
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
