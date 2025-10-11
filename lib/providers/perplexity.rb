require 'json'
require_relative 'base'
require_relative '../fetchers/perplexity'

module Providers
  class Perplexity < Base
    def can_pull_api_specs?
      false
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      true
    end

    def openapi_url
      # Perplexity doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://api.perplexity.ai/openapi.yaml'
    end

    def run
      # For Perplexity, we'll focus on fetching models data since they don't have a public OpenAPI spec
      # The openapi.yaml is manually maintained
      @logger.info("Perplexity provider: OpenAPI spec handling skipped (no public spec available)")

      # Fetch models using the fetcher
      processed_models = process_models
      if processed_models && !processed_models.empty?
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Perplexity models data using fetcher")
      else
        @logger.error("Failed to fetch models using fetcher, skipping update")
      end
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/perplexity"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models
      fetched_data = Fetchers::Perplexity.fetch
      return [] if fetched_data.empty?

      processed_models = fetched_data.map do |model|
        api_name = model[:api_name]
        next unless api_name

        specs = get_model_specs(api_name)
        family = extract_family(api_name)

        pricing = build_pricing(model)

        {
          'name' => model[:name] || api_name,
          'family' => family,
          'provider' => 'perplexity',
          'id' => api_name,
          'context_window' => specs[:context_window],
          'max_output_tokens' => specs[:max_output_tokens],
          'modalities' => {
            'input' => ['text'],
            'output' => ['text']
          },
          'capabilities' => ['search_grounding'],
          'pricing' => pricing
        }
      end.compact

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def get_model_specs(api_name)
      # Default specs
      default_specs = {
        context_window: 127072,
        max_output_tokens: 4096
      }

      # Specific specs for known models
      specs_map = {
        'sonar' => { context_window: 127072, max_output_tokens: 4096 },
        'sonar-pro' => { context_window: 200000, max_output_tokens: 8000 },
        'sonar-reasoning' => { context_window: 127072, max_output_tokens: 4096 },
        'sonar-reasoning-pro' => { context_window: 127072, max_output_tokens: 4096 },
        'sonar-deep-research' => { context_window: 127072, max_output_tokens: 4096 }
      }

      specs_map[api_name] || default_specs
    end

    def build_pricing(model)
      input_price = model[:input_price] || 1.0
      output_price = model[:output_price] || 1.0

      pricing = {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => input_price,
            'output_per_million' => output_price
          }
        }
      }

      # Add citation and reasoning pricing for deep research
      if model[:api_name] == 'sonar-deep-research'
        citation_price = model[:citation_price] || 2.0
        reasoning_price = model[:reasoning_price] || 3.0
        search_query_price = model[:search_query_price] || 5.0

        pricing['citation_tokens'] = {
          'standard' => {
            'input_per_million' => citation_price
          }
        }
        pricing['reasoning_tokens'] = {
          'standard' => {
            'input_per_million' => reasoning_price
          }
        }
        pricing['search_queries'] = {
          'per_thousand' => search_query_price
        }
      end

      pricing
    end

    def extract_family(model_id)
      case model_id
      when 'sonar'
        'sonar'
      when 'sonar-pro'
        'sonar-pro'
      when 'sonar-reasoning'
        'sonar-reasoning'
      when 'sonar-reasoning-pro'
        'sonar-reasoning-pro'
      when 'sonar-deep-research'
        'sonar-deep-research'
      else
        model_id
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.