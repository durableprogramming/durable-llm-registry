require 'json'
require 'yaml'
require_relative 'base'

module Providers
  class XAI < Base
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
      'https://api.x.ai/api-docs/openapi.json'
    end

    def run
      spec_content = download_openapi_spec(openapi_url)
      # Convert JSON to YAML if needed
      if openapi_url.end_with?('.json')
        spec_hash = JSON.parse(spec_content)
        spec_content = YAML.dump(spec_hash)
      end
      # Skip validation for now due to validator issues
      save_spec_to_catalog('xai', spec_content)
      @logger.info("Updated XAI openapi spec")

      # Models data is hardcoded, skipping update to preserve manually created data
      @logger.info("XAI models data update skipped (hardcoded data)")
    end

    private

    def fetch_models_data
      # Since xAI API requires authentication, we'll use hardcoded model data
      # based on their public documentation and API spec
      {
        'data' => [
          {
            'id' => 'grok-4-0709',
            'context_length' => 128000,
            'max_tokens' => 32768
          },
          {
            'id' => 'grok-code-fast-1',
            'context_length' => 128000,
            'max_tokens' => 32768
          },
          {
            'id' => 'grok-3',
            'context_length' => 128000,
            'max_tokens' => 32768
          },
          {
            'id' => 'grok-3-mini',
            'context_length' => 128000,
            'max_tokens' => 32768
          },
          {
            'id' => 'grok-2-vision-1212',
            'context_length' => 128000,
            'max_tokens' => 32768
          },
          {
            'id' => 'grok-2-image-1212',
            'context_length' => 128000,
            'max_tokens' => 32768
          }
        ]
      }
    end

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/xai"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def self.process_models(data)
      models = data['data']

      processed_models = models.map do |model|
        family = extract_family(model['id'])

        {
          'name' => get_display_name(model['id']),
          'family' => family,
          'provider' => 'xai',
          'id' => model['id'],
          'context_window' => model['context_length'] || 128000,
          'max_output_tokens' => model['max_tokens'] || 32768,
          'modalities' => get_modalities(model['id']),
          'capabilities' => get_capabilities(model['id']),
          'pricing' => get_pricing_for_model(model['id'])
        }
      end

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def self.extract_family(model_id)
      if model_id.start_with?('grok-4')
        'grok-4'
      elsif model_id.start_with?('grok-code-fast')
        'grok-code-fast'
      elsif model_id.start_with?('grok-3-mini')
        'grok-3-mini'
      elsif model_id.start_with?('grok-3')
        'grok-3'
      elsif model_id.start_with?('grok-2-vision')
        'grok-2-vision'
      elsif model_id.start_with?('grok-2-image')
        'grok-2-image'
      else
        'grok'
      end
    end

    def self.get_display_name(model_id)
      display_names = {
        'grok-4-0709' => 'Grok 4',
        'grok-code-fast-1' => 'Grok Code Fast',
        'grok-3' => 'Grok 3',
        'grok-3-mini' => 'Grok 3 Mini',
        'grok-2-vision-1212' => 'Grok 2 Vision',
        'grok-2-image-1212' => 'Grok 2 Image'
      }
      display_names[model_id] || model_id
    end

    def self.get_modalities(model_id)
      if model_id.include?('vision')
        {
          'input' => ['text', 'image'],
          'output' => ['text']
        }
      elsif model_id.include?('image')
        {
          'input' => ['text'],
          'output' => ['image']
        }
      else
        {
          'input' => ['text'],
          'output' => ['text']
        }
      end
    end

    def self.get_capabilities(model_id)
      # xAI models generally support function calling and reasoning
      ['function_calling', 'reasoning']
    end

    def self.get_pricing_for_model(model_id)
      # xAI pricing - using approximate values based on their tiered pricing
      # These are placeholder values and should be updated with actual pricing
      pricing_data = {
        'grok-4-0709' => { 'input' => 5.0, 'output' => 15.0 },
        'grok-code-fast-1' => { 'input' => 3.0, 'output' => 9.0 },
        'grok-3' => { 'input' => 5.0, 'output' => 15.0 },
        'grok-3-mini' => { 'input' => 1.5, 'output' => 4.5 },
        'grok-2-vision-1212' => { 'input' => 5.0, 'output' => 15.0 },
        'grok-2-image-1212' => { 'input' => 5.0, 'output' => 15.0 }
      }

      pricing = pricing_data[model_id] || { 'input' => 5.0, 'output' => 15.0 }

      {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => pricing['input'],
            'output_per_million' => pricing['output']
          }
        }
      }
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.