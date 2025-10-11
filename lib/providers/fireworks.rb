require 'json'
require_relative 'base'
require_relative '../fetchers/fireworks'

module Providers
  class Fireworks < Base
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
      # Fireworks doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://api.fireworks.ai/inference/v1/openapi.yaml'
    end

    def run
      # For Fireworks, we'll focus on fetching models data since they don't have a public OpenAPI spec
      # The openapi.yaml is manually maintained
      @logger.info("Fireworks provider: OpenAPI spec handling skipped (no public spec available)")

      # Fetch models using the new fetcher
      processed_models = process_models
      if processed_models && !processed_models.empty?
        save_models_to_jsonl(processed_models)
        @logger.info("Updated Fireworks models data using fetcher")
      else
        @logger.error("Failed to fetch models using fetcher, skipping update")
      end
    rescue StandardError => e
      @logger.error("Error in Fireworks provider run: #{e.message}")
      raise
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/fireworks-ai"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models
      fetched_data = Fetchers::Fireworks.fetch
      return [] if fetched_data.empty?

      processed_models = fetched_data.map do |model|
        api_name = model[:api_name]
        next unless api_name

        family = extract_family(api_name)
        pricing = build_pricing(model)
        max_output_tokens = get_max_output_tokens(api_name)

         {
           'name' => (model[:name].to_s.empty? ? api_name : model[:name]),
          'family' => family,
          'provider' => 'fireworks-ai',
          'id' => "accounts/fireworks/models/#{api_name}",
          'context_window' => model[:context_window] || 128000,
          'max_output_tokens' => max_output_tokens,
          'modalities' => model[:modalities] || { 'input' => ['text'], 'output' => ['text'] },
          'capabilities' => model[:capabilities] || [],
          'pricing' => pricing
        }
      end.compact

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def extract_family(api_name)
      # Extract family from API name
      if api_name.include?('deepseek')
        'deepseek-v3'
      elsif api_name.include?('kimi')
        'kimi-k2'
      elsif api_name.include?('gpt-oss')
        'gpt-oss'
      elsif api_name.include?('qwen3')
        if api_name.include?('coder')
          'qwen3-coder'
        else
          'qwen3'
        end
      elsif api_name.include?('qwen2p5')
        'qwen2p5-vl'
      elsif api_name.include?('llama4')
        if api_name.include?('maverick')
          'llama4-maverick'
        elsif api_name.include?('scout')
          'llama4-scout'
        else
          'llama4'
        end
      elsif api_name.include?('glm')
        'glm-4p5v'
      elsif api_name.include?('flux')
        if api_name.include?('kontext')
          'flux-kontext'
        else
          'flux-1'
        end
      elsif api_name.include?('asr') || api_name.include?('whisper')
        api_name
      else
        api_name.split('-').first(2).join('-')
      end
    end

    def build_pricing(model)
      pricing_info = model[:pricing] || {}

      # Handle different pricing types
      if pricing_info[:input_price] && pricing_info[:output_price]
        {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => pricing_info[:input_price],
              'output_per_million' => pricing_info[:output_price]
            }
          }
        }
      elsif pricing_info[:step_price]
        # Image generation per step
        {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => pricing_info[:step_price],
              'output_per_million' => pricing_info[:step_price]
            }
          }
        }
      elsif pricing_info[:image_price]
        # Per image pricing
        {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => pricing_info[:image_price],
              'output_per_million' => pricing_info[:image_price]
            }
          }
        }
      elsif pricing_info[:minute_price]
        # Audio per minute pricing
        {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => pricing_info[:minute_price],
              'output_per_million' => pricing_info[:minute_price]
            }
          }
        }
      else
        # Default pricing
        {
          'text_tokens' => {
            'standard' => {
              'input_per_million' => 0.5,
              'output_per_million' => 1.5
            }
          }
        }
      end
    end

    def get_max_output_tokens(api_name)
      # Default max output tokens based on model type
      if api_name.include?('asr') || api_name.include?('whisper')
        16000
      elsif api_name.include?('flux')
        4096
      elsif api_name.include?('deepseek') || api_name.include?('kimi')
        20000
      else
        4096
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.