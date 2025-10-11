require 'nokogiri'
require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class Fireworks
    MODELS_URL = 'https://app.fireworks.ai/models'

    TIMEOUT = 30
    MAX_RETRIES = 3
    RETRY_DELAY = 2

    class FetchError < StandardError; end

    attr_reader :logger

    def initialize(logger: ColoredLogger.new(STDOUT))
      @logger = logger
      @logger.level = Logger::WARN
    end

    def self.fetch(**options)
      new(**options).fetch
    end

    def fetch
      models = fetch_models
      return [] if models.empty?

      logger.info("Successfully fetched #{models.size} models")
      models
    rescue => e
      logger.error("Failed to fetch Fireworks data: #{e.class} - #{e.message}")
      []
    end

    private

    def fetch_models
      doc = fetch_html(MODELS_URL, "models page")
      return [] unless doc

      models = []

      # Parse model cards - each model is in a card with a link
      doc.css('a[href*="/models/fireworks/"]').each do |link|
        begin
          href = link['href']
          next unless href

          # Extract API name from href
          api_name_match = href.match(/\/models\/fireworks\/(.+)/)
          next unless api_name_match

          api_name = api_name_match[1]
          next unless valid_api_name?(api_name)

          # Extract model information from the card
          model_info = extract_model_info(link, api_name)
          next unless model_info

          models << model_info.merge(api_name: api_name)
        rescue => e
          logger.warn("Error parsing model card: #{e.message}")
          next
        end
      end

      deduplicated = models.uniq { |m| m[:api_name] }
      logger.info("Extracted #{deduplicated.size} unique models")
      deduplicated
    rescue => e
      logger.error("Error in fetch_models: #{e.class} - #{e.message}")
      []
    end

    def extract_model_info(card_element, api_name)
      # Find the model name - usually in a heading or strong text
      model_name = extract_model_name(card_element)
      return nil unless model_name

      # Extract pricing information
      pricing_info = extract_pricing(card_element)

      # Extract context window
      context_window = extract_context_window(card_element)

      # Extract capabilities
      capabilities = extract_capabilities(card_element)

      # Extract modalities based on model type
      modalities = extract_modalities(card_element, api_name)

      {
        name: model_name,
        pricing: pricing_info,
        context_window: context_window,
        capabilities: capabilities,
        modalities: modalities
      }.compact
    end

    def extract_model_name(card_element)
      # Try different selectors for model name
      name_selectors = [
        'h3', 'h4', '.font-bold', '.font-semibold',
        'strong', '[class*="font-bold"]', '[class*="font-semibold"]'
      ]

      name_selectors.each do |selector|
        element = card_element.css(selector).first
        next unless element

        text = safe_text(element).strip
        next if text.empty? || text.match?(/^\$[\d.]+/) # Skip pricing
        next if text.match?(/Context|Input|Output|Serverless|Tunable/i) # Skip metadata

        return text if text.length > 3 # Reasonable minimum length
      end

      nil
    end

    def extract_pricing(card_element)
      pricing = {}

      # Look for pricing text patterns
      text_content = card_element.text

      # Extract input/output pricing like "$0.56/M Input • $1.68/M Output"
      input_match = text_content.match(/\$([\d.]+)\/M Input/)
      output_match = text_content.match(/\$([\d.]+)\/M Output/)

      if input_match && output_match
        pricing[:input_price] = input_match[1].to_f
        pricing[:output_price] = output_match[1].to_f
      end

      # Extract per-token pricing like "$0.90/M Tokens"
      token_match = text_content.match(/\$([\d.]+)\/M Tokens/)
      if token_match
        price = token_match[1].to_f
        pricing[:input_price] = price
        pricing[:output_price] = price
      end

      # Extract per-step pricing like "$0.0005/step"
      step_match = text_content.match(/\$([\d.]+)\/step/)
      if step_match
        pricing[:step_price] = step_match[1].to_f
      end

      # Extract per-minute pricing like "$0.0032/minute"
      minute_match = text_content.match(/\$([\d.]+)\/minute/)
      if minute_match
        pricing[:minute_price] = minute_match[1].to_f
      end

      # Extract per-image pricing like "$0.04/ea"
      ea_match = text_content.match(/\$([\d.]+)\/ea/)
      if ea_match
        pricing[:image_price] = ea_match[1].to_f
      end

      # If no pricing found, check for specific model patterns
      if pricing.empty?
        # Some models might have pricing in different formats
        # For now, we'll leave it empty and let the provider handle defaults
      end

      pricing
    end

    def extract_context_window(card_element)
      text_content = card_element.text

      # Look for patterns like "160k Context", "128k Context", "1M Context"
      context_match = text_content.match(/(\d+(?:\.\d+)?)(k|M)\s+Context/i)
      if context_match
        number = context_match[1].to_f
        unit = context_match[2].downcase

        if unit == 'k'
          return (number * 1000).to_i
        elsif unit == 'm'
          return (number * 1_000_000).to_i
        end
      end

      # Default context windows for known model types
      nil # Let the provider set defaults
    end

    def extract_capabilities(card_element)
      capabilities = []

      text_content = card_element.text.downcase

      # Check for common capabilities
      capabilities << 'function_calling' if text_content.include?('function') || text_content.include?('tool')
      capabilities << 'fine_tuning' if text_content.include?('tunable') || text_content.include?('fine') || text_content.include?('train')
      capabilities << 'vision' if text_content.include?('vision') || text_content.include?('vl') || text_content.include?('glm-4p5v')
      capabilities << 'image_generation' if text_content.include?('flux') || text_content.include?('image') && text_content.include?('generation')
      capabilities << 'speech_to_text' if text_content.include?('asr') || text_content.include?('speech') || text_content.include?('whisper') || text_content.include?('audio')

      capabilities.uniq
    end

    def extract_modalities(card_element, api_name)
      text_content = card_element.text.downcase

      input_modalities = ['text']
      output_modalities = ['text']

      # Vision models
      if text_content.include?('vision') || api_name.include?('vl') || api_name.include?('glm-4p5v')
        input_modalities << 'image'
      end

      # Image generation models
      if text_content.include?('image') && text_content.include?('generation') || api_name.include?('flux')
        output_modalities << 'image'
      end

      # Audio models
      if text_content.include?('audio') || text_content.include?('asr') || text_content.include?('whisper') || api_name.include?('asr') || api_name.include?('whisper')
        input_modalities = ['audio']
        output_modalities = ['text']
      end

      # Llama 4 Maverick has vision
      if api_name.include?('llama4-maverick')
        input_modalities << 'image'
      end

      { input: input_modalities.uniq, output: output_modalities.uniq }
    end

    def fetch_html(url, description)
      retries = 0

      begin
        logger.debug("Fetching #{description} from #{url}")

        response = connection.get(url)

        unless response.success?
          raise FetchError, "HTTP #{response.status} for #{description}"
        end

        body = response.body
        if body.nil? || body.strip.empty?
          raise FetchError, "Empty response body for #{description}"
        end

        doc = Nokogiri::HTML(body)

        if doc.nil? || doc.children.empty?
          raise FetchError, "Failed to parse HTML for #{description}"
        end

        doc
      rescue Faraday::TimeoutError => e
        retries += 1
        if retries <= MAX_RETRIES
          logger.warn("Timeout fetching #{description}, retry #{retries}/#{MAX_RETRIES}")
          sleep(RETRY_DELAY * retries)
          retry
        end
        logger.error("Max retries reached for #{description}")
        nil
      rescue Faraday::Error, FetchError => e
        logger.error("Failed to fetch #{description}: #{e.message}")
        nil
      rescue => e
        logger.error("Unexpected error fetching #{description}: #{e.class} - #{e.message}")
        nil
      end
    end

    def connection
      @connection ||= HttpCache.new(timeout: TIMEOUT, open_timeout: TIMEOUT / 2)
    end

    def safe_text(element)
      return '' if element.nil?
      element.text.to_s.strip.gsub(/\s+/, ' ')
    rescue => e
      logger.warn("Error extracting text: #{e.message}")
      ''
    end

    def valid_api_name?(api_name)
      return false if api_name.nil? || api_name.empty?
      # Fireworks API names are typically lowercase with hyphens
      api_name.match?(/^[a-z0-9-]+(?:-[a-z0-9-]+)*$/) && !api_name.match?(/\s/)
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.