require 'json'
require_relative 'base'
require_relative '../fetchers/opencode_cli'

module Providers
  class OpencodeCli < Base
    def can_pull_api_specs?
      false # CLI output has no OpenAPI spec
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      true
    end

    def run
      models_by_provider = Fetchers::OpencodeCli.fetch
      if models_by_provider.nil? || models_by_provider.empty?
        @logger.error("Failed to fetch models using opencode CLI, skipping update")
        return
      end

      models_by_provider.each do |provider_id, raw_models|
        processed_models = process_models(provider_id, raw_models)
        next if processed_models.empty?

        save_models_to_jsonl(provider_id, processed_models)
        @logger.info("Updated outside_sources/opencode-cli/#{provider_id} models data (#{processed_models.size} models)")
      end
    end

    private

    SOURCE_NAME = 'opencode-cli'

    def save_models_to_jsonl(provider_id, models)
      catalog_dir = "catalog/outside_sources/#{SOURCE_NAME}/#{provider_id}"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models(provider_id, raw_models)
      processed = raw_models.map { |raw| convert_model(provider_id, raw) }.compact
      processed.sort_by! { |m| m['name'] }
      processed
    end

    def convert_model(provider_id, raw)
      id = raw['id']
      return nil if id.nil? || id.empty?

      {
        'name' => raw['name'] || id,
        'family' => raw['family'] || id,
        'provider' => provider_id,
        'id' => id,
        'context_window' => raw.dig('limit', 'context'),
        'max_output_tokens' => raw.dig('limit', 'output'),
        'modalities' => build_modalities(raw),
        'capabilities' => build_capabilities(raw),
        'pricing' => build_pricing(raw)
      }
    rescue => e
      @logger.warn("Error converting model #{id}: #{e.message}")
      nil
    end

    def build_modalities(raw)
      input = raw.dig('capabilities', 'input') || {}
      output = raw.dig('capabilities', 'output') || {}

      {
        'input' => input.select { |_, enabled| enabled }.keys,
        'output' => output.select { |_, enabled| enabled }.keys
      }
    end

    def build_capabilities(raw)
      capabilities = raw['capabilities'] || {}
      list = []
      list << 'function_calling' if capabilities['toolcall']
      list << 'reasoning' if capabilities['reasoning']
      list
    end

    def build_pricing(raw)
      cost = raw['cost'] || {}
      input_price = cost['input'].to_f
      output_price = cost['output'].to_f

      pricing = {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => input_price,
            'output_per_million' => output_price
          }
        }
      }

      cache = cost['cache'] || {}
      if cache['write'] || cache['read']
        pricing['text_tokens']['cached'] = {
          'input_per_million' => cache['write'].to_f,
          'output_per_million' => cache['read'].to_f
        }
      end

      pricing
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
