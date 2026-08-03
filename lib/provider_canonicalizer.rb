# Maps provider-name spellings from outside sources onto the canonical names
# used by our own native catalog/<provider> directories (see catalog/providers.json),
# so the same real-world provider isn't split into duplicate buckets like
# "mistral" vs "mistral-ai" or "azure-open-ai" vs "azure-openai".
class ProviderCanonicalizer
  CANONICAL_NAMES = %w[
    anthropic azure-openai cohere deepseek fireworks-ai google groq
    mistral-ai openai opencode-zen openrouter perplexity together xai
  ].freeze

  # Only true spelling/naming variants of the SAME product are aliased here.
  # Distinct products under one vendor (google-vertex vs google-gemini,
  # azure-ai-foundry vs azure-openai) are kept separate on purpose -- they
  # have different auth, pricing, and regional behavior, so collapsing them
  # would silently mix incompatible data.
  ALIASES = {
    'mistral' => 'mistral-ai',
    'azure-open-ai' => 'azure-openai',
    'together-ai' => 'together',
    'perplexity-ai' => 'perplexity'
  }.freeze

  def self.canonicalize(name)
    ALIASES[name] || name
  end

  def self.canonical?(name)
    CANONICAL_NAMES.include?(canonicalize(name))
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
