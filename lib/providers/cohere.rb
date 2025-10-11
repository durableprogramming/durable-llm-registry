require 'json'
require_relative 'base'

module Providers
  class Cohere < Base
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
      'https://raw.githubusercontent.com/cohere-ai/cohere-developer-experience/refs/heads/main/cohere-openapi.yaml'
    end

    def run
      # Download and save the OpenAPI spec
      @logger.info("Downloading Cohere OpenAPI spec...")
      spec_content = download_openapi_spec(openapi_url)
      if spec_content
        save_spec_to_catalog('cohere', spec_content)
        @logger.info("Updated Cohere OpenAPI spec")
      else
        @logger.error("Failed to download OpenAPI spec from #{openapi_url}")
        return
      end

      # Fetch models from API and save to models.jsonl
      models_data = fetch_models_from_api
      if models_data
        processed_models = process_models_from_api(models_data)
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Cohere models data from API")
      else
        @logger.error("Failed to fetch models from Cohere API, skipping update to preserve manually created data")
      end
    end

    private

    def fetch_models_from_api
      # Cohere doesn't have a public models endpoint that we can access without auth; eventually we'll implement something else with secrets.
      nil
    end

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/cohere"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models_from_api(data)
      # Process API response data from Cohere's models endpoint
      # Since we can't fetch from API without auth, this is a placeholder
      process_models(nil)
    end

    def process_models(data)
      # Hardcoded model data based on Cohere's documentation
      models = [
        # Command A models
        {
          id: 'command-a-03-2025',
          display_name: 'Command A 03-2025',
          family: 'command-a',
          context_window: 256000,
          max_output_tokens: 8000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'tool_use', 'reasoning'],
          pricing_input: 15.0,
          pricing_output: 75.0
        },
        {
          id: 'command-a-reasoning-08-2025',
          display_name: 'Command A Reasoning 08-2025',
          family: 'command-a-reasoning',
          context_window: 256000,
          max_output_tokens: 32000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'tool_use', 'reasoning'],
          pricing_input: 15.0,
          pricing_output: 75.0
        },
        {
          id: 'command-a-translate-08-2025',
          display_name: 'Command A Translate 08-2025',
          family: 'command-a-translate',
          context_window: 8000,
          max_output_tokens: 8000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['translation'],
          pricing_input: 15.0,
          pricing_output: 75.0
        },
        {
          id: 'command-a-vision-07-2025',
          display_name: 'Command A Vision 07-2025',
          family: 'command-a-vision',
          context_window: 128000,
          max_output_tokens: 8000,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['vision', 'function_calling', 'tool_use'],
          pricing_input: 15.0,
          pricing_output: 75.0
        },
        # Command R models
        {
          id: 'command-r7b-12-2024',
          display_name: 'Command R7B 12-2024',
          family: 'command-r7b',
          context_window: 128000,
          max_output_tokens: 4000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'tool_use', 'rag'],
          pricing_input: 2.5,
          pricing_output: 10.0
        },
        {
          id: 'command-r-08-2024',
          display_name: 'Command R 08-2024',
          family: 'command-r',
          context_window: 128000,
          max_output_tokens: 4000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'tool_use', 'rag'],
          pricing_input: 2.5,
          pricing_output: 10.0
        },
        {
          id: 'command-r-plus-08-2024',
          display_name: 'Command R+ 08-2024',
          family: 'command-r-plus',
          context_window: 128000,
          max_output_tokens: 4000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'tool_use', 'rag'],
          pricing_input: 2.5,
          pricing_output: 10.0
        },
        # Embed models
        {
          id: 'embed-v4.0',
          display_name: 'Embed v4.0',
          family: 'embed-v4',
          context_window: 128000,
          max_output_tokens: nil,
          input_modalities: ['text', 'image'],
          output_modalities: ['embedding'],
          capabilities: ['embedding', 'multimodal'],
          pricing_input: 0.1, # per 1000 tokens
          pricing_output: nil
        },
        {
          id: 'embed-english-v3.0',
          display_name: 'Embed English v3.0',
          family: 'embed-english-v3',
          context_window: 512,
          max_output_tokens: nil,
          input_modalities: ['text', 'image'],
          output_modalities: ['embedding'],
          capabilities: ['embedding'],
          pricing_input: 0.1, # per 1000 tokens
          pricing_output: nil
        },
        {
          id: 'embed-english-light-v3.0',
          display_name: 'Embed English Light v3.0',
          family: 'embed-english-light-v3',
          context_window: 512,
          max_output_tokens: nil,
          input_modalities: ['text', 'image'],
          output_modalities: ['embedding'],
          capabilities: ['embedding'],
          pricing_input: 0.1, # per 1000 tokens
          pricing_output: nil
        },
        {
          id: 'embed-multilingual-v3.0',
          display_name: 'Embed Multilingual v3.0',
          family: 'embed-multilingual-v3',
          context_window: 512,
          max_output_tokens: nil,
          input_modalities: ['text', 'image'],
          output_modalities: ['embedding'],
          capabilities: ['embedding', 'multilingual'],
          pricing_input: 0.1, # per 1000 tokens
          pricing_output: nil
        },
        {
          id: 'embed-multilingual-light-v3.0',
          display_name: 'Embed Multilingual Light v3.0',
          family: 'embed-multilingual-light-v3',
          context_window: 512,
          max_output_tokens: nil,
          input_modalities: ['text', 'image'],
          output_modalities: ['embedding'],
          capabilities: ['embedding', 'multilingual'],
          pricing_input: 0.1, # per 1000 tokens
          pricing_output: nil
        },
        # Rerank models
        {
          id: 'rerank-v3.5',
          display_name: 'Rerank v3.5',
          family: 'rerank-v3.5',
          context_window: 4096,
          max_output_tokens: nil,
          input_modalities: ['text'],
          output_modalities: ['ranking'],
          capabilities: ['reranking'],
          pricing_input: 2.0, # per 1000 searches
          pricing_output: nil
        },
        {
          id: 'rerank-english-v3.0',
          display_name: 'Rerank English v3.0',
          family: 'rerank-english-v3',
          context_window: 4096,
          max_output_tokens: nil,
          input_modalities: ['text'],
          output_modalities: ['ranking'],
          capabilities: ['reranking'],
          pricing_input: 2.0, # per 1000 searches
          pricing_output: nil
        },
        {
          id: 'rerank-multilingual-v3.0',
          display_name: 'Rerank Multilingual v3.0',
          family: 'rerank-multilingual-v3',
          context_window: 4096,
          max_output_tokens: nil,
          input_modalities: ['text'],
          output_modalities: ['ranking'],
          capabilities: ['reranking', 'multilingual'],
          pricing_input: 2.0, # per 1000 searches
          pricing_output: nil
        },
        # Aya models
        {
          id: 'c4ai-aya-expanse-8b',
          display_name: 'Aya Expanse 8B',
          family: 'aya-expanse',
          context_window: 8000,
          max_output_tokens: 4000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['multilingual'],
          pricing_input: 0.5,
          pricing_output: 1.5
        },
        {
          id: 'c4ai-aya-expanse-32b',
          display_name: 'Aya Expanse 32B',
          family: 'aya-expanse',
          context_window: 128000,
          max_output_tokens: 4000,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['multilingual'],
          pricing_input: 0.5,
          pricing_output: 1.5
        },
        {
          id: 'c4ai-aya-vision-8b',
          display_name: 'Aya Vision 8B',
          family: 'aya-vision',
          context_window: 16000,
          max_output_tokens: 4000,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['multilingual', 'vision'],
          pricing_input: 0.5,
          pricing_output: 1.5
        },
        {
          id: 'c4ai-aya-vision-32b',
          display_name: 'Aya Vision 32B',
          family: 'aya-vision',
          context_window: 16000,
          max_output_tokens: 4000,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['multilingual', 'vision'],
          pricing_input: 0.5,
          pricing_output: 1.5
        }
      ]

      processed_models = models.map do |model|
        pricing = if model[:pricing_input] && model[:pricing_output]
                    {
                      'text_tokens' => {
                        'standard' => {
                          'input_per_million' => model[:pricing_input],
                          'output_per_million' => model[:pricing_output]
                        }
                      }
                    }
                  elsif model[:pricing_input] && model[:id].include?('embed')
                    {
                      'text_tokens' => {
                        'standard' => {
                          'input_per_thousand' => model[:pricing_input]
                        }
                      }
                    }
                  elsif model[:pricing_input] && model[:id].include?('rerank')
                    {
                      'search' => {
                        'per_thousand' => model[:pricing_input]
                      }
                    }
                  else
                    nil
                  end

        {
          'name' => model[:display_name],
          'family' => model[:family],
          'provider' => 'cohere',
          'id' => model[:id],
          'context_window' => model[:context_window],
          'max_output_tokens' => model[:max_output_tokens],
          'modalities' => {
            'input' => model[:input_modalities],
            'output' => model[:output_modalities]
          },
          'capabilities' => model[:capabilities],
          'pricing' => pricing
        }.compact
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.