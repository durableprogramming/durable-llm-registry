require 'json'
require_relative 'base'

module Providers
  class Deepseek < Base
    def can_pull_api_specs?
      true
    end

    def can_pull_model_info?
      false
    end

    def can_pull_pricing?
      false
    end

    def openapi_url
      'https://raw.githubusercontent.com/api-evangelist/deepseek/refs/heads/main/openapi/deepseek-chat-completion-api-openapi.yml'
    end

    def run
      # Download and save the OpenAPI spec
      @logger.info("Downloading Deepseek OpenAPI spec...")
      spec_content = download_openapi_spec(openapi_url)
      if spec_content
        save_spec_to_catalog('deepseek', spec_content)
        @logger.info("Updated Deepseek OpenAPI spec")
      else
        @logger.error("Failed to download OpenAPI spec from #{openapi_url}")
        return
      end

      @logger.info("Deepseek models data update skipped (no API integration)")
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/deepseek"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models(data)
      # Hardcoded model data based on available information from Deepseek and partners
      models = [
        {
          id: 'deepseek-chat',
          display_name: 'DeepSeek Chat',
          family: 'deepseek-chat',
          context_window: 128000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.07, output_per_million: 0.28 }
            }
          }
        },
        {
          id: 'deepseek-coder',
          display_name: 'DeepSeek Coder',
          family: 'deepseek-coder',
          context_window: 128000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.07, output_per_million: 0.28 }
            }
          }
        },
        {
          id: 'deepseek-reasoner',
          display_name: 'DeepSeek Reasoner',
          family: 'deepseek-reasoner',
          context_window: 64000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.40, output_per_million: 1.75 }
            }
          }
        }
      ]

      processed_models = models.map do |model|
        {
          'name' => model[:display_name],
          'family' => model[:family],
          'provider' => 'deepseek',
          'id' => model[:id],
          'context_window' => model[:context_window],
          'max_output_tokens' => model[:max_output_tokens],
          'modalities' => {
            'input' => model[:input_modalities],
            'output' => model[:output_modalities]
          },
          'capabilities' => model[:capabilities],
          'pricing' => model[:pricing]
        }
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.