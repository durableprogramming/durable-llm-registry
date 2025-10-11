require 'json'
require_relative 'base'
require_relative '../fetchers/opencode'

module Providers
  class Opencode < Base
    def can_pull_api_specs?
      false # Zen is a gateway, doesn't have its own OpenAPI spec
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      true
    end

    def run
      # Fetch models using the fetcher
      processed_models = process_models
      if processed_models && !processed_models.empty?
        save_models_to_jsonl(processed_models)
        @logger.info("Updated OpenCode Zen models data using fetcher")
      else
        @logger.error("Failed to fetch models using fetcher, skipping update")
      end
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/opencode-zen"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models
      fetched_data = Fetchers::Opencode.fetch
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
          'provider' => 'opencode-zen',
          'id' => api_name,
          'context_window' => specs[:context_window],
          'max_output_tokens' => specs[:max_output_tokens],
          'modalities' => specs[:modalities],
          'capabilities' => specs[:capabilities],
          'pricing' => pricing
        }
      end.compact

      processed_models.sort_by! { |m| m['name'] }
      processed_models
    end

    def get_model_specs(api_name)
      # Default specs
      default_specs = {
        context_window: 128000,
        max_output_tokens: 4096,
        modalities: {
          'input' => ['text'],
          'output' => ['text']
        },
        capabilities: ['function_calling']
      }

      # Specific specs for known models
      specs_map = {
        'gpt-5' => {
          context_window: 128000,
          max_output_tokens: 16384,
          modalities: { 'input' => ['text'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'gpt-5-codex' => {
          context_window: 128000,
          max_output_tokens: 16384,
          modalities: { 'input' => ['text'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'claude-sonnet-4-5' => {
          context_window: 200000,
          max_output_tokens: 8192,
          modalities: { 'input' => ['text', 'image'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'claude-sonnet-4' => {
          context_window: 200000,
          max_output_tokens: 8192,
          modalities: { 'input' => ['text', 'image'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'claude-3-5-haiku' => {
          context_window: 200000,
          max_output_tokens: 8192,
          modalities: { 'input' => ['text', 'image'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'claude-opus-4-1' => {
          context_window: 200000,
          max_output_tokens: 32000,
          modalities: { 'input' => ['text', 'image'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'qwen3-coder' => {
          context_window: 128000,
          max_output_tokens: 4096,
          modalities: { 'input' => ['text'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'grok-code' => {
          context_window: 128000,
          max_output_tokens: 4096,
          modalities: { 'input' => ['text'], 'output' => ['text'] },
          capabilities: ['function_calling']
        },
        'kimi-k2' => {
          context_window: 128000,
          max_output_tokens: 4096,
          modalities: { 'input' => ['text'], 'output' => ['text'] },
          capabilities: ['function_calling']
        }
      }

      specs_map[api_name] || default_specs
    end

    def build_pricing(model)
      input_price = model[:input_price] || 1.0
      output_price = model[:output_price] || 5.0
      cache_write_price = model[:cache_write_price] || input_price * 1.25
      cache_hit_price = model[:cache_hit_price] || output_price * 0.1

      pricing = {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => input_price,
            'output_per_million' => output_price
          }
        }
      }

      # Add cached pricing if available
      if cache_write_price && cache_write_price > 0
        pricing['text_tokens']['cached'] = {
          'input_per_million' => cache_write_price,
          'output_per_million' => cache_hit_price || output_price
        }
      end

      pricing
    end

    def extract_family(model_id)
      if model_id.start_with?('gpt-')
        'gpt'
      elsif model_id.start_with?('claude-')
        model_id.split('-')[0..2].join('-')
      elsif model_id == 'qwen3-coder'
        'qwen3'
      elsif model_id == 'grok-code'
        'grok'
      elsif model_id == 'kimi-k2'
        'kimi'
      else
        model_id.split('-').first
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.