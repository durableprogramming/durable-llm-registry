require 'json'
require_relative 'base'
require_relative '../fetchers/spider_rs'

module Providers
  class SpiderRs < Base
    SOURCE_NAME = 'spider-rs'

    def can_pull_api_specs?
      false
    end

    def can_pull_model_info?
      true
    end

    def can_pull_pricing?
      true
    end

    def run
      raw_models = Fetchers::SpiderRs.fetch
      if raw_models.nil? || raw_models.empty?
        @logger.error("Failed to fetch models using spider-rs/llm_models, skipping update")
        return
      end

      processed_models = process_models(raw_models)
      save_models_to_jsonl(processed_models)
      @logger.info("Updated outside_sources/#{SOURCE_NAME} models data (#{processed_models.size} models)")
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/outside_sources/#{SOURCE_NAME}"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models(raw_models)
      processed = raw_models.map { |raw| convert_model(raw) }.compact
      processed.sort_by! { |m| m['name'] }
      processed
    end

    def convert_model(raw)
      name = raw[:name]
      return nil if name.nil? || name.empty?

      {
        'name' => name,
        'family' => name,
        'provider' => guess_provider(name),
        'id' => name,
        'context_window' => raw[:max_input_tokens],
        'max_output_tokens' => raw[:max_output_tokens],
        'modalities' => build_modalities(raw),
        'capabilities' => [],
        'pricing' => build_pricing(raw),
        'arena_score' => raw[:arena_score]
      }
    rescue => e
      @logger.warn("Error converting model #{name}: #{e.message}")
      nil
    end

    # spider-rs's flat model list has no real provider grouping (names like
    # "qwen3-coder" or "code-llama-13b" carry no reliable vendor signal by
    # themselves). Rather than guess from string structure, every model is
    # tagged with this one placeholder provider; CatalogMerger reassigns each
    # model to a real provider when its id exactly matches a model already
    # known from a higher-priority source.
    UNMATCHED_PROVIDER = 'spider-rs-unmatched'.freeze

    def guess_provider(_name)
      UNMATCHED_PROVIDER
    end

    def build_modalities(raw)
      input = %w[text]
      input << 'image' if raw[:supports_vision]
      input << 'audio' if raw[:supports_audio]
      input << 'video' if raw[:supports_video]
      input << 'pdf' if raw[:supports_pdf]

      { 'input' => input, 'output' => ['text'] }
    end

    def build_pricing(raw)
      {
        'text_tokens' => {
          'standard' => {
            'input_per_million' => raw[:input_cost_per_million],
            'output_per_million' => raw[:output_cost_per_million]
          }
        }
      }
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
