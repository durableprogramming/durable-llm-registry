require 'json'
require_relative 'base'

module Providers
  class AzureOpenai < Base
    def can_pull_api_specs?
      false
    end

    def can_pull_model_info?
      false
    end

    def can_pull_pricing?
      false
    end

    def openapi_url
      # Azure OpenAI doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://api.openai.azure.com/v1/openapi.yaml'
    end

    def run
      # For Azure OpenAI, we'll focus on fetching models data since they don't have a public OpenAPI spec
      # The openapi.yaml is manually maintained
      @logger.info("Azure OpenAI provider: OpenAPI spec handling skipped (no public spec available)")

      # Fetch models from API and save to models.jsonl
      models_data = fetch_models_from_api
      if models_data
        processed_models = process_models_from_api(models_data)
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Azure OpenAI models data from API")
      else
        @logger.error("Failed to fetch models from Azure OpenAI API, skipping update to preserve manually created data")
      end
    end

    private

    def fetch_models_from_api
      # This would require an API key and Azure subscription, so for now we'll use hardcoded data
      # In a real implementation, you'd make an HTTP request to Azure's model listing endpoint
      # with proper authentication headers
      nil
    end

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/azure-openai"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models_from_api(data)
      # Process API response data from Azure OpenAI's models endpoint
      # Since we can't fetch from API without auth, this is a placeholder
      self.class.process_models(nil)
    end

    def self.process_models(data)
      # Since we can't fetch from API without auth, we'll use hardcoded model data
      # based on Azure OpenAI documentation
      models = [
        {
          id: 'gpt-4o',
          display_name: 'GPT-4o',
          context_window: 128000,
          max_output_tokens: 16384
        },
        {
          id: 'gpt-4o-mini',
          display_name: 'GPT-4o mini',
          context_window: 128000,
          max_output_tokens: 16384
        },
        {
          id: 'gpt-4-turbo',
          display_name: 'GPT-4 Turbo',
          context_window: 128000,
          max_output_tokens: 4096
        },
        {
          id: 'gpt-4',
          display_name: 'GPT-4',
          context_window: 8192,
          max_output_tokens: 4096
        },
        {
          id: 'gpt-35-turbo',
          display_name: 'GPT-3.5 Turbo',
          context_window: 16384,
          max_output_tokens: 4096
        }
      ]

      processed_models = models.map do |model|
        family = extract_family(model[:id])

        {
          'name' => model[:display_name],
          'family' => family,
          'provider' => 'azure-openai',
          'id' => model[:id],
          'context_window' => model[:context_window],
          'max_output_tokens' => model[:max_output_tokens],
          'modalities' => {
            'input' => ['text'],
            'output' => ['text']
          },
          'capabilities' => ['function_calling'],
          'pricing' => get_pricing_for_model(model[:id])
        }
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def self.extract_family(model_id)
      case model_id
      when 'gpt-4o'
        'gpt-4o'
      when 'gpt-4o-mini'
        'gpt-4o-mini'
      when 'gpt-4-turbo'
        'gpt-4-turbo'
      when 'gpt-4'
        'gpt-4'
      when 'gpt-35-turbo'
        'gpt-3.5-turbo'
      else
        model_id
      end
    end

    def self.get_pricing_for_model(model_id)
      pricing_data = {
        'gpt-4o' => {
          'input_per_million' => 2.5,
          'output_per_million' => 10.0
        },
        'gpt-4o-mini' => {
          'input_per_million' => 0.15,
          'output_per_million' => 0.6
        },
        'gpt-4-turbo' => {
          'input_per_million' => 10.0,
          'output_per_million' => 30.0
        },
        'gpt-4' => {
          'input_per_million' => 30.0,
          'output_per_million' => 60.0
        },
        'gpt-35-turbo' => {
          'input_per_million' => 0.5,
          'output_per_million' => 1.5
        }
      }

      pricing = pricing_data[model_id] || {
        'input_per_million' => 2.5,
        'output_per_million' => 10.0
      }

      {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => pricing['input_per_million'],
            'output_per_million' => pricing['output_per_million']
          }
        }
      }
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.