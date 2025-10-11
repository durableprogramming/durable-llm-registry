require 'json'
require_relative 'base'
require_relative '../fetchers/anthropic'

module Providers
  class Anthropic < Base
    def can_pull_api_specs?
      true
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      true
    end

    def openapi_url
      'https://storage.googleapis.com/stainless-sdk-openapi-specs/anthropic%2Fanthropic-9c7d1ea59095c76b24f14fe279825c2b0dc10f165a973a46b8a548af9aeda62e.yml'
    end

    def run
      # Download and save the OpenAPI spec
      @logger.info("Downloading Anthropic OpenAPI spec...")
      spec_content = download_openapi_spec(openapi_url)
      if spec_content
        save_spec_to_catalog('anthropic', spec_content)
        @logger.info("Updated Anthropic OpenAPI spec")
      else
        @logger.error("Failed to download OpenAPI spec from #{openapi_url}")
        return
      end

      # Fetch models using the new fetcher
      processed_models = process_models
      if processed_models && !processed_models.empty?
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Anthropic models data using fetcher")
      else
        @logger.error("Failed to fetch models using fetcher, skipping update")
      end
    end

    private



    def save_models_to_jsonl(models)
      catalog_dir = "catalog/anthropic"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models
      fetched_data = Fetchers::Anthropic.fetch
      return [] if fetched_data.nil? || fetched_data.empty?

       processed_models = fetched_data.map do |model|
         api_name = model[:api_name]
         next unless api_name && !api_name.empty?

        specs = get_model_specs(api_name)
        family = extract_family(api_name)

        pricing = build_pricing(model)

        {
          'name' => model[:name] || api_name,
          'family' => family,
          'provider' => 'anthropic',
          'id' => api_name,
          'context_window' => specs[:context_window],
          'max_output_tokens' => specs[:max_output_tokens],
          'modalities' => {
            'input' => ['text', 'image'],
            'output' => ['text']
          },
          'capabilities' => ['function_calling'],
          'pricing' => pricing
        }
      end.compact

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def get_model_specs(api_name)
      # Default specs
      default_specs = {
        context_window: 200000,
        max_output_tokens: 4096
      }

      # Specific specs for known models
      specs_map = {
        'claude-opus-4-1-20250805' => { context_window: 200000, max_output_tokens: 32000 },
        'claude-opus-4-20250514' => { context_window: 200000, max_output_tokens: 32000 },
        'claude-sonnet-4-20250514' => { context_window: 200000, max_output_tokens: 64000 },
        'claude-3-7-sonnet-20250219' => { context_window: 200000, max_output_tokens: 64000 },
        'claude-3-5-haiku-20241022' => { context_window: 200000, max_output_tokens: 8192 },
        'claude-3-haiku-20240307' => { context_window: 200000, max_output_tokens: 4096 }
      }

      specs_map[api_name] || default_specs
    end

    def build_pricing(model)
      input_price = model[:input_price] || 3.0
      output_price = model[:output_price] || 15.0
      cache_write_price = model[:cache_write_price] || input_price * 1.25
      cache_hit_price = model[:cache_hit_price] || output_price

      {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => input_price,
            'output_per_million' => output_price
          },
          'cached' => {
            'input_per_million' => cache_write_price,
            'output_per_million' => cache_hit_price
          }
        }
      }
    end

    def extract_family(model_id)
      if model_id.include?('opus-4-1')
        'claude-opus-4-1'
      elsif model_id.include?('opus-4')
        'claude-opus-4'
      elsif model_id.include?('sonnet-4')
        'claude-sonnet-4'
      elsif model_id.include?('3-7-sonnet')
        'claude-3-7-sonnet'
      elsif model_id.include?('3-5-haiku')
        'claude-3-5-haiku'
      elsif model_id.include?('3-haiku')
        'claude-3-haiku'
      else
        model_id.split('-').first(2).join('-')
      end
    end


  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.