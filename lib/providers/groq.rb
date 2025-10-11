require 'json'
require_relative 'base'

module Providers
  class Groq < Base
    def can_pull_api_specs?
      false
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      false
    end

    def openapi_url
      # Groq doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://api.groq.com/openai/v1/openapi.yaml'
    end

    def run
      # For Groq, we'll try to fetch models from API first
      # The openapi.yaml is manually maintained
      @logger.info("Groq provider: OpenAPI spec handling skipped (no public spec available)")

      # Try to fetch models from API
      models_data = fetch_models_from_api
      if models_data
        processed_models = process_models_from_api(models_data)
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Groq models data from API")
      else
        @logger.error("Failed to fetch models from Groq API, skipping update to preserve manually created data")
      end
    end

    private

    def fetch_models_from_api
      # Try to fetch from Groq's models API
      uri = URI('https://api.groq.com/openai/v1/models')
      response = Net::HTTP.get(uri)

      begin
        data = JSON.parse(response)
        data['data'] if data['data']
      rescue JSON::ParserError
        nil
      end
    rescue StandardError
      nil
    end

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/groq"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models_from_api(data)
      # Process API response data from Groq's models endpoint
      # The API returns models in OpenAI-compatible format
      processed_models = data.map do |model|
        # Extract family from model ID
        family = extract_family(model['id'])

        # Get pricing for this model (would need to be maintained separately)
        pricing = get_pricing_for_model(model['id'])

        {
          'name' => model['id'], # API doesn't provide display names, use ID as fallback
          'family' => family,
          'provider' => 'groq',
          'id' => model['id'],
          'context_window' => model['context_window'],
          'max_output_tokens' => model['max_output_tokens'],
          'modalities' => {
            'input' => ['text'], # Default assumption
            'output' => ['text']
          },
          'capabilities' => [], # Would need to be determined based on model
          'pricing' => pricing
        }.compact
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def extract_family(model_id)
      # Extract family name from model ID
      case model_id
      when /^llama-3\.1-8b/
        'llama-3.1-8b'
      when /^llama-3\.3-70b/
        'llama-3.3-70b'
      when /llama-guard/
        'llama-guard'
      when /gpt-oss-120b/
        'gpt-oss-120b'
      when /gpt-oss-20b/
        'gpt-oss-20b'
      when /whisper/
        'whisper'
      when /compound/
        'groq-compound'
      else
        model_id.split('/').last.split('-').first(2).join('-')
      end
    end

    def get_pricing_for_model(model_id)
      # Pricing data - would need to be kept in sync with Groq's pricing
      pricing_data = {
        'llama-3.1-8b-instant' => { input: 0.05, output: 0.08 },
        'llama-3.3-70b-versatile' => { input: 0.59, output: 0.79 },
        'meta-llama/llama-guard-4-12b' => { input: 0.20, output: 0.20 },
        'openai/gpt-oss-120b' => { input: 0.15, output: 0.75 },
        'openai/gpt-oss-20b' => { input: 0.10, output: 0.50 },
        'whisper-large-v3' => nil, # Audio pricing
        'whisper-large-v3-turbo' => nil,
        'groq/compound' => nil, # Passed through
        'groq/compound-mini' => nil,
        'meta-llama/llama-4-maverick-17b-128e-instruct' => { input: 0.20, output: 0.60 },
        'meta-llama/llama-4-scout-17b-16e-instruct' => { input: 0.11, output: 0.34 },
        'moonshotai/kimi-k2-instruct-0905' => { input: 1.00, output: 3.00 },
        'qwen/qwen3-32b' => { input: 0.29, output: 0.59 },
        'playai-tts' => nil, # Character-based pricing
        'playai-tts-arabic' => nil
      }

      pricing = pricing_data[model_id]
      if pricing
        {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => pricing[:input],
              'output_per_million' => pricing[:output]
            }
          }
        }
      else
        nil
      end
    end

    def process_models(data)
      # Hardcoded model data based on Groq's documentation
      models = [
        {
          id: 'llama-3.1-8b-instant',
          display_name: 'Llama 3.1 8B Instant',
          family: 'llama-3.1-8b',
          context_window: 131072,
          max_output_tokens: 131072,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.05,
          pricing_output: 0.08
        },
        {
          id: 'llama-3.3-70b-versatile',
          display_name: 'Llama 3.3 70B Versatile',
          family: 'llama-3.3-70b',
          context_window: 131072,
          max_output_tokens: 32768,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.59,
          pricing_output: 0.79
        },
        {
          id: 'meta-llama/llama-guard-4-12b',
          display_name: 'Llama Guard 4 12B',
          family: 'llama-guard-4-12b',
          context_window: 131072,
          max_output_tokens: 1024,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: [],
          pricing_input: 0.20,
          pricing_output: 0.20
        },
        {
          id: 'openai/gpt-oss-120b',
          display_name: 'GPT-OSS 120B',
          family: 'gpt-oss-120b',
          context_window: 131072,
          max_output_tokens: 65536,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'reasoning'],
          pricing_input: 0.15,
          pricing_output: 0.75
        },
        {
          id: 'openai/gpt-oss-20b',
          display_name: 'GPT-OSS 20B',
          family: 'gpt-oss-20b',
          context_window: 131072,
          max_output_tokens: 65536,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'reasoning'],
          pricing_input: 0.10,
          pricing_output: 0.50
        },
        {
          id: 'whisper-large-v3',
          display_name: 'Whisper Large v3',
          family: 'whisper-large-v3',
          context_window: nil,
          max_output_tokens: nil,
          input_modalities: ['audio'],
          output_modalities: ['text'],
          capabilities: ['speech_to_text'],
          pricing_input: nil, # Audio pricing is per hour
          pricing_output: nil
        },
        {
          id: 'whisper-large-v3-turbo',
          display_name: 'Whisper Large v3 Turbo',
          family: 'whisper-large-v3-turbo',
          context_window: nil,
          max_output_tokens: nil,
          input_modalities: ['audio'],
          output_modalities: ['text'],
          capabilities: ['speech_to_text'],
          pricing_input: nil,
          pricing_output: nil
        },
        {
          id: 'groq/compound',
          display_name: 'Groq Compound',
          family: 'groq-compound',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['web_search', 'code_execution', 'tool_use'],
          pricing_input: nil, # Pricing passed through to underlying models
          pricing_output: nil
        },
        {
          id: 'groq/compound-mini',
          display_name: 'Groq Compound Mini',
          family: 'groq-compound-mini',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['web_search', 'code_execution', 'tool_use'],
          pricing_input: nil,
          pricing_output: nil
        },
        {
          id: 'meta-llama/llama-4-maverick-17b-128e-instruct',
          display_name: 'Llama 4 Maverick (17Bx128E)',
          family: 'llama-4-maverick',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.20,
          pricing_output: 0.60
        },
        {
          id: 'meta-llama/llama-4-scout-17b-16e-instruct',
          display_name: 'Llama 4 Scout (17Bx16E)',
          family: 'llama-4-scout',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.11,
          pricing_output: 0.34
        },
        {
          id: 'moonshotai/kimi-k2-instruct-0905',
          display_name: 'Kimi K2 0905',
          family: 'kimi-k2-0905',
          context_window: 262144,
          max_output_tokens: 16384,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 1.00,
          pricing_output: 3.00
        },
        {
          id: 'qwen/qwen3-32b',
          display_name: 'Qwen3 32B',
          family: 'qwen3-32b',
          context_window: 131072,
          max_output_tokens: 40960,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.29,
          pricing_output: 0.59
        },
        {
          id: 'playai-tts',
          display_name: 'PlayAI TTS',
          family: 'playai-tts',
          context_window: 8192,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['audio'],
          capabilities: ['text_to_speech'],
          pricing_input: nil, # Character-based pricing
          pricing_output: nil
        },
        {
          id: 'playai-tts-arabic',
          display_name: 'PlayAI TTS Arabic',
          family: 'playai-tts-arabic',
          context_window: 8192,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['audio'],
          capabilities: ['text_to_speech'],
          pricing_input: nil,
          pricing_output: nil
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
                  else
                    nil
                  end

        {
          'name' => model[:display_name],
          'family' => model[:family],
          'provider' => 'groq',
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