require 'json'
require_relative 'base'

module Providers
  class Together < Base
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
      # Together doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://api.together.xyz/v1/openapi.yaml'
    end

    def run
      # For Together, we'll focus on fetching models data since they don't have a public OpenAPI spec
      # The openapi.yaml is manually maintained
      @logger.info("Together provider: OpenAPI spec handling skipped (no public spec available)")

      # No API fetching implemented, skipping models update to preserve manually created data
      @logger.info("Together models data update skipped (no API integration)")
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/together"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models(data)
      # Hardcoded model data based on the current catalog information from Together docs
      models = [
        # Chat models
        {
          id: 'meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8',
          display_name: 'Llama 4 Maverick (17Bx128E)',
          family: 'llama-4-maverick',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.27,
          pricing_output: 0.85
        },
        {
          id: 'meta-llama/Llama-4-Scout-17B-16E-Instruct',
          display_name: 'Llama 4 Scout (17Bx16E)',
          family: 'llama-4-scout',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.18,
          pricing_output: 0.59
        },
        {
          id: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
          display_name: 'Llama 3.3 70B Instruct Turbo',
          family: 'llama-3.3-70b',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.88,
          pricing_output: 0.88
        },
        {
          id: 'meta-llama/Llama-3.2-3B-Instruct-Turbo',
          display_name: 'Llama 3.2 3B Instruct Turbo',
          family: 'llama-3.2-3b',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.06,
          pricing_output: 0.06
        },
        {
          id: 'meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo',
          display_name: 'Llama 3.1 405B Instruct Turbo',
          family: 'llama-3.1-405b',
          context_window: 130815,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 3.50,
          pricing_output: 3.50
        },
        {
          id: 'meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo',
          display_name: 'Llama 3.1 70B Instruct Turbo',
          family: 'llama-3.1-70b',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.88,
          pricing_output: 0.88
        },
        {
          id: 'meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo',
          display_name: 'Llama 3.1 8B Instruct Turbo',
          family: 'llama-3.1-8b',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.18,
          pricing_output: 0.18
        },
        {
          id: 'meta-llama/Meta-Llama-3-8B-Instruct-Lite',
          display_name: 'Llama 3 8B Instruct Lite',
          family: 'llama-3-8b-lite',
          context_window: 8192,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.10,
          pricing_output: 0.10
        },
        {
          id: 'meta-llama/Meta-Llama-3-70b-chat-hf',
          display_name: 'Llama 3 70B Instruct Reference',
          family: 'llama-3-70b-reference',
          context_window: 8192,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.88,
          pricing_output: 0.88
        },
        {
          id: 'meta-llama/Llama-3-70b-chat-hf-turbo',
          display_name: 'Llama 3 70B Instruct Turbo',
          family: 'llama-3-70b-turbo',
          context_window: 8192,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.88,
          pricing_output: 0.88
        },
        {
          id: 'meta-llama/Llama-2-70b-hf',
          display_name: 'LLaMA-2 (70B)',
          family: 'llama-2-70b',
          context_window: 4096,
          max_output_tokens: 2048,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: [],
          pricing_input: 0.90,
          pricing_output: 0.90
        },
        # DeepSeek models
        {
          id: 'deepseek-ai/DeepSeek-R1',
          display_name: 'DeepSeek-R1',
          family: 'deepseek-r1',
          context_window: 163839,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 3.00,
          pricing_output: 7.00
        },
        {
          id: 'deepseek-ai/DeepSeek-R1-Distill-Qwen-14B',
          display_name: 'DeepSeek R1 Distill Qwen 14B',
          family: 'deepseek-r1-distill-qwen-14b',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.18,
          pricing_output: 0.18
        },
        {
          id: 'deepseek-ai/DeepSeek-R1-Distill-Llama-70B',
          display_name: 'DeepSeek R1 Distill Llama 70B',
          family: 'deepseek-r1-distill-llama-70b',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 2.00,
          pricing_output: 2.00
        },
        {
          id: 'deepseek-ai/DeepSeek-R1-0528-tput',
          display_name: 'DeepSeek R1-0528-tput',
          family: 'deepseek-r1-0528-tput',
          context_window: 163839,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.55,
          pricing_output: 2.19
        },
        {
          id: 'deepseek-ai/DeepSeek-V3.1',
          display_name: 'DeepSeek-V3.1',
          family: 'deepseek-v3.1',
          context_window: 128000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.60,
          pricing_output: 1.70
        },
        {
          id: 'deepseek-ai/DeepSeek-V3',
          display_name: 'DeepSeek-V3',
          family: 'deepseek-v3',
          context_window: 163839,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 1.25,
          pricing_output: 1.25
        },
        # OpenAI models
        {
          id: 'openai/gpt-oss-120b',
          display_name: 'GPT-OSS 120B',
          family: 'gpt-oss-120b',
          context_window: 128000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.15,
          pricing_output: 0.60
        },
        {
          id: 'openai/gpt-oss-20b',
          display_name: 'GPT-OSS 20B',
          family: 'gpt-oss-20b',
          context_window: 128000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.05,
          pricing_output: 0.20
        },
        # Qwen models
        {
          id: 'Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8',
          display_name: 'Qwen3-Coder 480B A35B Instruct',
          family: 'qwen3-coder-480b',
          context_window: 256000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 2.00,
          pricing_output: 2.00
        },
        {
          id: 'Qwen/Qwen3-235B-A22B-Instruct-2507-tput',
          display_name: 'Qwen3 235B A22B Instruct 2507 FP8',
          family: 'qwen3-235b-a22b-instruct',
          context_window: 262144,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.20,
          pricing_output: 0.60
        },
        {
          id: 'Qwen/Qwen3-235B-A22B-Thinking-2507',
          display_name: 'Qwen3 235B A22B Thinking 2507 FP8',
          family: 'qwen3-235b-a22b-thinking',
          context_window: 262144,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.65,
          pricing_output: 3.00
        },
        {
          id: 'Qwen/Qwen3-235B-A22B-fp8-tput',
          display_name: 'Qwen3 235B A22B FP8 Throughput',
          family: 'qwen3-235b-a22b-tput',
          context_window: 40960,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.20,
          pricing_output: 0.60
        },
        {
          id: 'Qwen/Qwen2.5-72B-Instruct-Turbo',
          display_name: 'Qwen 2.5 72B',
          family: 'qwen2.5-72b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 1.20,
          pricing_output: 1.20
        },
        {
          id: 'Qwen/Qwen2.5-VL-72B-Instruct',
          display_name: 'Qwen2.5-VL 72B Instruct',
          family: 'qwen2.5-vl-72b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text', 'image'],
          output_modalities: ['text'],
          capabilities: ['vision', 'function_calling'],
          pricing_input: 1.95,
          pricing_output: 8.00
        },
        {
          id: 'Qwen/Qwen2.5-Coder-32B-Instruct',
          display_name: 'Qwen2.5 Coder 32B Instruct',
          family: 'qwen2.5-coder-32b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.80,
          pricing_output: 0.80
        },
        {
          id: 'Qwen/Qwen2.5-7B-Instruct-Turbo',
          display_name: 'Qwen2.5 7B Instruct Turbo',
          family: 'qwen2.5-7b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.30,
          pricing_output: 0.30
        },
        {
          id: 'Qwen/QwQ-32B',
          display_name: 'Qwen QwQ-32B',
          family: 'qwq-32b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 1.20,
          pricing_output: 1.20
        },
        # GLM models
        {
          id: 'zai-org/GLM-4.5-Air-FP8',
          display_name: 'GLM-4.5-Air',
          family: 'glm-4.5-air',
          context_window: 131072,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.20,
          pricing_output: 1.10
        },
        # Kimi models
        {
          id: 'moonshotai/Kimi-K2-Instruct',
          display_name: 'Kimi K2 Instruct',
          family: 'kimi-k2',
          context_window: 128000,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 1.00,
          pricing_output: 3.00
        },
        {
          id: 'moonshotai/Kimi-K2-Instruct-0905',
          display_name: 'Kimi K2 0905',
          family: 'kimi-k2-0905',
          context_window: 262144,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 1.00,
          pricing_output: 3.00
        },
        # Mistral models
        {
          id: 'mistralai/Mistral-7B-Instruct-v0.2',
          display_name: 'Mistral (7B) Instruct v0.2',
          family: 'mistral-7b-v0.2',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.20,
          pricing_output: 0.20
        },
        {
          id: 'mistralai/Mistral-7B-Instruct-v0.1',
          display_name: 'Mistral Instruct',
          family: 'mistral-7b-v0.1',
          context_window: 8192,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.20,
          pricing_output: 0.20
        },
        {
          id: 'mistralai/Mistral-Small-24B-Instruct-2501',
          display_name: 'Mistral Small 3',
          family: 'mistral-small-3',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.80,
          pricing_output: 0.80
        },
        {
          id: 'mistralai/Mixtral-8x7B-v0.1',
          display_name: 'Mixtral 8x7B Instruct v0.1',
          family: 'mixtral-8x7b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.60,
          pricing_output: 0.60
        },
        # Other models
        {
          id: 'marin-community/marin-8b-instruct',
          display_name: 'Marin 8B Instruct',
          family: 'marin-8b',
          context_window: 4096,
          max_output_tokens: 2048,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.18,
          pricing_output: 0.18
        },
        {
          id: 'google/gemma-2b-it',
          display_name: 'Gemma Instruct (2B)',
          family: 'gemma-2b',
          context_window: 8192,
          max_output_tokens: 4096,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.02,
          pricing_output: 0.04
        },
        {
          id: 'google/gemma-3n-E4B-it',
          display_name: 'Gemma 3N E4B Instruct',
          family: 'gemma-3n-e4b',
          context_window: 32768,
          max_output_tokens: 8192,
          input_modalities: ['text'],
          output_modalities: ['text'],
          capabilities: ['function_calling'],
          pricing_input: 0.02,
          pricing_output: 0.04
        }
      ]

      processed_models = models.map do |model|
        {
          'name' => model[:display_name],
          'family' => model[:family],
          'provider' => 'together',
          'id' => model[:id],
          'context_window' => model[:context_window],
          'max_output_tokens' => model[:max_output_tokens],
          'modalities' => {
            'input' => model[:input_modalities],
            'output' => model[:output_modalities]
          },
          'capabilities' => model[:capabilities],
          'pricing' => {
            'text_tokens' => {
              'standard' => {
                'input_per_million' => model[:pricing_input],
                'output_per_million' => model[:pricing_output]
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