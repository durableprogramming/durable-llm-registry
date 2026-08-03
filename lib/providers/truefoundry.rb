require 'json'
require_relative 'base'
require_relative '../fetchers/truefoundry'

module Providers
  class Truefoundry < Base
    SOURCE_NAME = 'truefoundry'

    def can_pull_api_specs?
      false
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      true
    end

    def run
      models_by_provider = Fetchers::Truefoundry.fetch
      if models_by_provider.nil? || models_by_provider.empty?
        @logger.error("Failed to fetch models using truefoundry/models, skipping update")
        return
      end

      models_by_provider.each do |provider_name, raw_models|
        processed_models = process_models(provider_name, raw_models)
        next if processed_models.empty?

        save_models_to_jsonl(provider_name, processed_models)
        @logger.info("Updated input_sources/external/#{SOURCE_NAME}/#{provider_name} models data (#{processed_models.size} models)")
      end
    end

    private

    def save_models_to_jsonl(provider_name, models)
      catalog_dir = "input_sources/external/#{SOURCE_NAME}/#{provider_name}"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models(provider_name, raw_models)
      processed = raw_models.map { |raw| convert_model(provider_name, raw) }.compact
      processed.sort_by! { |m| m['name'] }
      processed
    end

    def convert_model(provider_name, raw)
      data = raw[:data]
      id = data['model']
      return nil if id.nil? || id.empty?

      model = {
        'name' => id,
        'family' => id,
        'provider' => provider_name,
        'id' => id,
        'context_window' => data.dig('limits', 'context_window') || data.dig('limits', 'max_input_tokens'),
        'max_output_tokens' => data.dig('limits', 'max_output_tokens'),
        'modalities' => build_modalities(data),
        'capabilities' => data['features'] || [],
        'pricing' => build_pricing(data)
      }
      model['upstream_vendor'] = raw[:upstream_vendor] if raw[:upstream_vendor]
      model
    rescue => e
      @logger.warn("Error converting model #{id}: #{e.message}")
      nil
    end

    def build_modalities(data)
      modalities = data['modalities'] || {}
      {
        'input' => modalities['input'] || ['text'],
        'output' => modalities['output'] || ['text']
      }
    end

    def build_pricing(data)
      costs = data['costs'] || []
      cost = costs.find { |c| c['region'] == '*' } || costs.first || {}

      pricing = {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => to_per_million(cost['input_cost_per_token']),
            'output_per_million' => to_per_million(cost['output_cost_per_token'])
          }
        }
      }

      cache_read = cost['cache_read_input_token_cost']
      cache_write = cost['cache_creation_input_token_cost']
      if cache_read || cache_write
        pricing['text_tokens']['cached'] = {
          'input_per_million' => to_per_million(cache_write),
          'output_per_million' => to_per_million(cache_read)
        }
      end

      pricing
    end

    def to_per_million(cost_per_token)
      return nil if cost_per_token.nil?

      Float(cost_per_token) * 1_000_000
    rescue ArgumentError, TypeError
      nil
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
