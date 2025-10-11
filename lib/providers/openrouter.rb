require 'json'
require_relative 'base'

module Providers
  class OpenRouter < Base
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
      'https://openrouter.ai/api/v1/openapi.yaml'  # Placeholder URL
    end

    def run
      # OpenRouter openapi spec is manually maintained, skip download
      @logger.info("OpenRouter provider: OpenAPI spec handling skipped (manually maintained)")

      # Fetch models from API and save to models.jsonl
      models_data = fetch_models_from_api
      if models_data
        processed_models = self.class.process_models(models_data)
        save_models_to_jsonl(processed_models)
        @logger.info("Updated OpenRouter models data from API")
      else
        @logger.error("Failed to fetch models from API")
      end
    end

    private

    def fetch_models_from_api
      uri = URI('https://openrouter.ai/api/v1/models')
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    rescue => e
      @logger.error("Error fetching models from OpenRouter API: #{e.message}")
      nil
    end

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/openrouter"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def self.process_models(data)
      models = data['data']

      processed_models = models.map do |model|
        provider_name, = model['id'].split('/', 2)
        family = provider_name

        # Map modalities
        input_modalities = model['architecture']['input_modalities'].map do |mod|
          case mod
          when 'text' then 'text'
          when 'image' then 'image'
          when 'audio' then 'audio'
          else mod
          end
        end

        output_modalities = model['architecture']['output_modalities'].map do |mod|
          case mod
          when 'text' then 'text'
          when 'image' then 'image'
          else mod
          end
        end

        # Pricing: convert per-token to per-million
        prompt_per_token = model['pricing']['prompt'].to_f
        completion_per_token = model['pricing']['completion'].to_f
        input_per_million = (prompt_per_token * 1_000_000).round(6)
        output_per_million = (completion_per_token * 1_000_000).round(6)

        # Handle max_output_tokens safely
        max_output_tokens = model.dig('top_provider', 'max_completion_tokens')

        {
          'name' => model['name'],
          'family' => family,
          'provider' => 'openrouter',
          'id' => model['id'],
          'context_window' => model['context_length'],
          'max_output_tokens' => max_output_tokens,
          'modalities' => {
            'input' => input_modalities,
            'output' => output_modalities
          },
          'capabilities' => [],
          'pricing' => {
            'text_tokens' => {
              'standard' => {
                'input_per_million' => input_per_million,
                'output_per_million' => output_per_million
              }
            }
          }
        }
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.