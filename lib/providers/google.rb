require 'json'
require_relative 'base'

module Providers
  class Google < Base
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
      # Google doesn't provide a public OpenAPI spec, so we'll use a placeholder
      'https://generativelanguage.googleapis.com/v1/openapi.yaml'
    end

    def run
      # For Google, we'll focus on fetching models data since they don't have a public OpenAPI spec
      # The openapi.yaml is manually maintained
      @logger.info("Google provider: OpenAPI spec handling skipped (no public spec available)")

      # No API fetching implemented, skipping models update to preserve manually created data
      @logger.info("Google models data update skipped (no API integration)")
    end

    private

    def save_models_to_jsonl(models)
      catalog_dir = "catalog/google"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
    end

    def process_models(data)
      # Hardcoded model data based on the current catalog information
      models = [
        {
          id: 'gemini-1.5-pro',
          display_name: 'Gemini 1.5 Pro',
          family: 'gemini-1.5-pro',
          context_window: 2097152,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 1.25, output_per_million: 5.0 },
              cached: { input_per_million: 0.3125, output_per_million: 5.0 }
            }
          }
        },
        {
          id: 'gemini-1.5-pro-001',
          display_name: 'Gemini 1.5 Pro',
          family: 'gemini-1.5-pro',
          context_window: 2097152,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 1.25, output_per_million: 5.0 },
              cached: { input_per_million: 0.3125, output_per_million: 5.0 }
            }
          }
        },
        {
          id: 'gemini-1.5-pro-002',
          display_name: 'Gemini 1.5 Pro',
          family: 'gemini-1.5-pro',
          context_window: 2097152,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 1.25, output_per_million: 5.0 },
              cached: { input_per_million: 0.3125, output_per_million: 5.0 }
            }
          }
        },
        {
          id: 'gemini-1.5-pro-latest',
          display_name: 'Gemini 1.5 Pro',
          family: 'gemini-1.5-pro',
          context_window: 2097152,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 1.25, output_per_million: 5.0 },
              cached: { input_per_million: 0.3125, output_per_million: 5.0 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash',
          display_name: 'Gemini 1.5 Flash',
          family: 'gemini-1.5-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash-001',
          display_name: 'Gemini 1.5 Flash',
          family: 'gemini-1.5-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash-002',
          display_name: 'Gemini 1.5 Flash',
          family: 'gemini-1.5-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash-latest',
          display_name: 'Gemini 1.5 Flash',
          family: 'gemini-1.5-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash-8b',
          display_name: 'Gemini 1.5 Flash-8B',
          family: 'gemini-1.5-flash-8b',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash-8b-001',
          display_name: 'Gemini 1.5 Flash-8B',
          family: 'gemini-1.5-flash-8b',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-1.5-flash-8b-latest',
          display_name: 'Gemini 1.5 Flash-8B',
          family: 'gemini-1.5-flash-8b',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.075, output_per_million: 0.3 },
              cached: { input_per_million: 0.01875, output_per_million: 0.3 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash',
          display_name: 'Gemini 2.0 Flash',
          family: 'gemini-2.0-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 },
              batch: { input_per_million: 0.05, output_per_million: 0.2 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash-001',
          display_name: 'Gemini 2.0 Flash',
          family: 'gemini-2.0-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 },
              batch: { input_per_million: 0.05, output_per_million: 0.2 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash-exp',
          display_name: 'Gemini 2.0 Flash',
          family: 'gemini-2.0-flash',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 },
              batch: { input_per_million: 0.05, output_per_million: 0.2 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash-live-001',
          display_name: 'Gemini 2.0 Flash Live',
          family: 'gemini-2.0-flash-live-001',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'text'],
          output_modalities: ['audio', 'text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash-lite',
          display_name: 'Gemini 2.0 Flash-Lite',
          family: 'gemini-2.0-flash-lite',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 },
              batch: { input_per_million: 0.05, output_per_million: 0.2 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash-lite-001',
          display_name: 'Gemini 2.0 Flash-Lite',
          family: 'gemini-2.0-flash-lite',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 },
              batch: { input_per_million: 0.05, output_per_million: 0.2 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash',
          display_name: 'Gemini 2.5 Flash',
          family: 'gemini-2.5-flash',
          context_window: 1048576,
          max_output_tokens: 65536,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 },
              batch: { input_per_million: 0.15, output_per_million: 1.25 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash-preview-05-20',
          display_name: 'Gemini 2.5 Flash',
          family: 'gemini-2.5-flash',
          context_window: 1048576,
          max_output_tokens: 65536,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 },
              batch: { input_per_million: 0.15, output_per_million: 1.25 }
            }
          }
        },
        {
          id: 'gemini-live-2.5-flash-preview',
          display_name: 'Gemini 2.5 Flash Live',
          family: 'gemini-live-2.5-flash-preview',
          context_window: 1048576,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'text'],
          output_modalities: ['audio', 'text'],
          capabilities: ['function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash-lite',
          display_name: 'Gemini 2.5 Flash-Lite',
          family: 'gemini-2.5-flash-lite',
          context_window: 1048576,
          max_output_tokens: 65536,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 },
              batch: { input_per_million: 0.15, output_per_million: 1.25 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash-lite-06-17',
          display_name: 'Gemini 2.5 Flash-Lite',
          family: 'gemini-2.5-flash-lite',
          context_window: 1048576,
          max_output_tokens: 65536,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 },
              batch: { input_per_million: 0.15, output_per_million: 1.25 }
            }
          }
        },
        {
          id: 'gemini-2.5-pro',
          display_name: 'Gemini 2.5 Pro',
          family: 'gemini-2.5-pro',
          context_window: 1048576,
          max_output_tokens: 65536,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['text'],
          capabilities: ['batch', 'function_calling', 'structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 1.25, output_per_million: 10.0 },
              cached: { input_per_million: 0.31, output_per_million: 10.0 },
              batch: { input_per_million: 0.625, output_per_million: 5.0 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash-exp-native-audio-thinking-dialog',
          display_name: 'Gemini 2.5 Flash Native Audio',
          family: 'gemini-2.5-flash-preview-native-audio-dialog',
          context_window: 128000,
          max_output_tokens: 8000,
          input_modalities: ['audio', 'text'],
          output_modalities: ['audio', 'text'],
          capabilities: ['function_calling'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash-preview-native-audio-dialog',
          display_name: 'Gemini 2.5 Flash Native Audio',
          family: 'gemini-2.5-flash-preview-native-audio-dialog',
          context_window: 128000,
          max_output_tokens: 8000,
          input_modalities: ['audio', 'text'],
          output_modalities: ['audio', 'text'],
          capabilities: ['function_calling'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 }
            }
          }
        },
        {
          id: 'gemini-2.0-flash-preview-image-generation',
          display_name: 'Gemini 2.0 Flash Preview Image Generation',
          family: 'gemini-2.0-flash-preview-image-generation',
          context_window: 32000,
          max_output_tokens: 8192,
          input_modalities: ['audio', 'image', 'text'],
          output_modalities: ['image', 'text'],
          capabilities: ['structured_output'],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.1, output_per_million: 0.4 },
              cached: { input_per_million: 0.025, output_per_million: 0.4 }
            }
          }
        },
        {
          id: 'gemini-2.5-flash-preview-tts',
          display_name: 'Gemini 2.5 Flash Preview Text-to-Speech',
          family: 'gemini-2.5-flash-preview-tts',
          context_window: 8000,
          max_output_tokens: 16000,
          input_modalities: ['text'],
          output_modalities: ['audio'],
          capabilities: [],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 0.3, output_per_million: 2.5 },
              cached: { input_per_million: 0.075, output_per_million: 2.5 }
            }
          }
        },
        {
          id: 'gemini-2.5-pro-preview-tts',
          display_name: 'Gemini 2.5 Pro Preview Text-to-Speech',
          family: 'gemini-2.5-pro-preview-tts',
          context_window: 8000,
          max_output_tokens: 16000,
          input_modalities: ['text'],
          output_modalities: ['audio'],
          capabilities: [],
          pricing: {
            text_tokens: {
              standard: { input_per_million: 1.25, output_per_million: 10.0 },
              cached: { input_per_million: 0.31, output_per_million: 10.0 }
            }
          }
        }
      ]

      processed_models = models.map do |model|
        {
          'name' => model[:display_name],
          'family' => model[:family],
          'provider' => 'google',
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