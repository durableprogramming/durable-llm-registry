require 'json'
require_relative 'base'

module Providers
  class Mistral < Base
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
      # Mistral doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://api.mistral.ai/v1/openapi.yaml'
    end

    def run
      # For Mistral, we'll try to fetch models from API first
      # The openapi.yaml is manually maintained
      @logger.info("Mistral provider: OpenAPI spec handling skipped (no public spec available)")

      # Try to fetch models from API
      models_data = fetch_models_from_api
      if models_data
        processed_models = process_models_from_api(models_data)
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Mistral models data from API")
      else
        @logger.error("Failed to fetch models from Mistral API, skipping update to preserve manually created data")
      end
    end

    private

    def fetch_models_from_api
      # Try to fetch from Mistral's models API
      uri = URI('https://api.mistral.ai/v1/models')
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
      catalog_dir = "catalog/mistral-ai"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models_from_api(data)
      # Process API response data from Mistral's models endpoint
      processed_models = data.map do |model|
        # Extract family from model ID
        family = extract_family(model['id'])

        # Get pricing for this model (would need to be maintained separately)
        pricing = get_pricing_for_model(model['id'])

        {
          'name' => model['id'], # API doesn't provide display names, use ID as fallback
          'family' => family,
          'provider' => 'mistral-ai',
          'id' => model['id'],
          'context_window' => model['max_context_length'] || 128000,
          'max_output_tokens' => model['max_tokens'] || 4096,
          'modalities' => {
            'input' => ['text'], # Default assumption
            'output' => ['text']
          },
          'capabilities' => model['capabilities'] || [],
          'pricing' => pricing
        }.compact
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def extract_family(model_id)
      # Extract family name from model ID
      case model_id
      when /^mistral-medium/
        'mistral-medium'
      when /^mistral-large/
        'mistral-large'
      when /^mistral-small/
        'mistral-small'
      when /^ministral/
        'ministral'
      when /^codestral/
        'codestral'
      when /^pixtral/
        'pixtral'
      when /^devstral/
        'devstral'
      when /^magistral/
        'magistral'
       when /^voxtral-small/
         'voxtral-small'
      when /^mistral-embed/
        'mistral-embed'
      when /^mistral-moderation/
        'mistral-moderation'
      when /^mistral-ocr/
        'mistral-ocr'
      else
        model_id.split('-').first(2).join('-')
      end
    end

    def get_pricing_for_model(model_id)
      # Pricing data - would need to be kept in sync with Mistral's pricing
      # These are placeholder values based on typical pricing
      pricing_data = {
        'mistral-medium-2508' => { input: 2.5, output: 7.5 },
        'mistral-medium-2505' => { input: 2.5, output: 7.5 },
        'mistral-large-2411' => { input: 4.0, output: 12.0 },
        'mistral-small-2506' => { input: 0.15, output: 0.6 },
        'mistral-small-2503' => { input: 0.15, output: 0.6 },
        'mistral-small-2501' => { input: 0.15, output: 0.6 },
        'ministral-3b-2410' => { input: 0.04, output: 0.04 },
        'ministral-8b-2410' => { input: 0.1, output: 0.1 },
        'codestral-2508' => { input: 0.2, output: 0.6 },
        'codestral-2501' => { input: 0.2, output: 0.6 },
        'pixtral-large-2411' => { input: 2.0, output: 6.0 },
        'pixtral-12b-2409' => { input: 0.15, output: 0.6 },
        'open-mistral-nemo' => { input: 0.15, output: 0.6 },
        'mistral-embed' => { input: 0.1, output: 0.0 },
        'codestral-embed' => { input: 0.1, output: 0.0 },
        'mistral-moderation-2411' => { input: 0.1, output: 0.0 },
        'mistral-ocr-2505' => { input: 0.1, output: 0.0 },
        'devstral-medium-2507' => { input: 2.5, output: 7.5 },
        'devstral-small-2507' => { input: 0.15, output: 0.6 },
        'magistral-medium-2509' => { input: 3.0, output: 9.0 },
        'magistral-small-2509' => { input: 0.2, output: 0.8 },
        'voxtral-small-2507' => { input: 0.2, output: 0.8 },
        'voxtral-mini-2507' => { input: 0.1, output: 0.4 }
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
      # Hardcoded model data based on Mistral's documentation
      models = [
        # Premier models
        {
          id: 'mistral-medium-2508',
          display_name: 'Mistral Medium 3.1',
          family: 'mistral-medium',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision'],
          pricing_input: 2.5,
          pricing_output: 7.5
        },
        {
          id: 'magistral-medium-2509',
          display_name: 'Magistral Medium 1.2',
          family: 'magistral-medium',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision', 'reasoning'],
          pricing_input: 3.0,
          pricing_output: 9.0
        },
        {
          id: 'codestral-2508',
          display_name: 'Codestral 2508',
          family: 'codestral',
          context_window: 256000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'code_generation', 'fill_in_the_middle'],
          pricing_input: 0.2,
          pricing_output: 0.6
        },
        {
          id: 'voxtral-mini-2507',
          display_name: 'Voxtral Mini Transcribe',
          family: 'voxtral-mini',
          context_window: nil,
          max_output_tokens: nil,
          input_modalities: ['audio'],
          output_modalities: ['text'],
          capabilities: ['speech_to_text'],
          pricing_input: nil,
          pricing_output: nil
        },
        {
          id: 'devstral-medium-2507',
          display_name: 'Devstral Medium',
          family: 'devstral-medium',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'code_generation', 'tool_use'],
          pricing_input: 2.5,
          pricing_output: 7.5
        },
        {
          id: 'mistral-ocr-2505',
          display_name: 'Mistral OCR 2505',
          family: 'mistral-ocr',
          context_window: nil,
          max_output_tokens: nil,
          input_modalities: ['image'],
          output_modalities: ['text'],
          capabilities: ['ocr'],
          pricing_input: nil,
          pricing_output: nil
        },
        {
          id: 'ministral-3b-2410',
          display_name: 'Ministral 3B',
          family: 'ministral-3b',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.04,
          pricing_output: 0.04
        },
        {
          id: 'ministral-8b-2410',
          display_name: 'Ministral 8B',
          family: 'ministral-8b',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.1,
          pricing_output: 0.1
        },
        {
          id: 'mistral-medium-2505',
          display_name: 'Mistral Medium 3',
          family: 'mistral-medium',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision'],
          pricing_input: 2.5,
          pricing_output: 7.5
        },
        {
          id: 'mistral-large-2411',
          display_name: 'Mistral Large 2.1',
          family: 'mistral-large',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'reasoning'],
          pricing_input: 4.0,
          pricing_output: 12.0
        },
        {
          id: 'codestral-2501',
          display_name: 'Codestral 2501',
          family: 'codestral',
          context_window: 256000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'code_generation', 'fill_in_the_middle'],
          pricing_input: 0.2,
          pricing_output: 0.6
        },
        {
          id: 'pixtral-large-2411',
          display_name: 'Pixtral Large',
          family: 'pixtral-large',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision'],
          pricing_input: 2.0,
          pricing_output: 6.0
        },
        {
          id: 'mistral-small-2407',
          display_name: 'Mistral Small 2',
          family: 'mistral-small',
          context_window: 32000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.15,
          pricing_output: 0.6
        },
        {
          id: 'mistral-embed',
          display_name: 'Mistral Embed',
          family: 'mistral-embed',
          context_window: 8000,
          max_output_tokens: nil,
          input_modalities: ['text'],
          output_modalities: ['embedding'],
          capabilities: ['embeddings'],
          pricing_input: 0.1,
          pricing_output: 0.0
        },
        {
          id: 'codestral-embed',
          display_name: 'Codestral Embed',
          family: 'codestral-embed',
          context_window: 8000,
          max_output_tokens: nil,
          input_modalities: ['text'],
          output_modalities: ['embedding'],
          capabilities: ['embeddings'],
          pricing_input: 0.1,
          pricing_output: 0.0
        },
        {
          id: 'mistral-moderation-2411',
          display_name: 'Mistral Moderation',
          family: 'mistral-moderation',
          context_window: 8000,
          max_output_tokens: nil,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['moderation'],
          pricing_input: 0.1,
          pricing_output: 0.0
        },
        # Open models
        {
          id: 'magistral-small-2509',
          display_name: 'Magistral Small 1.2',
          family: 'magistral-small',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision', 'reasoning'],
          pricing_input: 0.2,
          pricing_output: 0.8
        },
        {
          id: 'voxtral-small-2507',
          display_name: 'Voxtral Small',
          family: 'voxtral-small',
          context_window: 32000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'audio'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'speech_to_text'],
          pricing_input: 0.2,
          pricing_output: 0.8
        },
        {
          id: 'voxtral-mini-2507',
          display_name: 'Voxtral Mini',
          family: 'voxtral-mini',
          context_window: 32000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'audio'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'speech_to_text'],
          pricing_input: 0.1,
          pricing_output: 0.4
        },
        {
          id: 'mistral-small-2506',
          display_name: 'Mistral Small 3.2',
          family: 'mistral-small',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.15,
          pricing_output: 0.6
        },
        {
          id: 'devstral-small-2507',
          display_name: 'Devstral Small 1.1',
          family: 'devstral-small',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'code_generation', 'tool_use'],
          pricing_input: 0.15,
          pricing_output: 0.6
        },
        {
          id: 'mistral-small-2503',
          display_name: 'Mistral Small 3.1',
          family: 'mistral-small',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision'],
          pricing_input: 0.15,
          pricing_output: 0.6
        },
        {
          id: 'mistral-small-2501',
          display_name: 'Mistral Small 3',
          family: 'mistral-small',
          context_window: 32000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.15,
          pricing_output: 0.6
        },
        {
          id: 'pixtral-12b-2409',
          display_name: 'Pixtral 12B',
          family: 'pixtral-12b',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'vision'],
          pricing_input: 0.15,
          pricing_output: 0.6
        },
        {
          id: 'open-mistral-nemo',
          display_name: 'Mistral Nemo 12B',
          family: 'mistral-nemo',
          context_window: 128000,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.15,
          pricing_output: 0.6
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
          'provider' => 'mistral-ai',
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