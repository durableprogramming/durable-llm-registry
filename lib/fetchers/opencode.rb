require 'nokogiri'
require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class Opencode
    MODELS_URL = 'https://opencode.ai/docs/zen/'
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
      pricing = fetch_pricing

      return [] if models.empty?

      # Combine models and pricing data
      combined = models.map do |model|
        next unless model[:api_name]
        model.merge(pricing[model[:api_name]] || {})
      end.compact

      logger.info("Successfully fetched #{combined.size} models")
      combined
    rescue => e
      logger.error("Failed to fetch OpenCode Zen data: #{e.class} - #{e.message}")
      []
    end

    private

    def fetch_models
      doc = fetch_html(MODELS_URL, "models page")
      return [] unless doc

      models = []

      # Parse endpoints table
      doc.css('table').each do |table|
        begin
          rows = table.css('tr')
          next if rows.empty?

          # Get header to determine column positions
          headers = rows.first.css('th, td').map { |h| safe_text(h).downcase }
          next unless headers.any? { |h| h.include?('model id') || h.include?('endpoint') }

          rows[1..-1]&.each do |row|
            begin
              cells = row.css('td')
              next if cells.empty?

              model_name = safe_text(cells[0])
              api_name = safe_text(cells[1])
              endpoint = safe_text(cells[2])

              # Skip header rows and empty entries
              next if model_name.empty? || api_name.empty?
              next if header_row?(model_name)

              models << {
                name: model_name,
                api_name: api_name,
                endpoint: endpoint
              }.compact
            rescue => e
              logger.warn("Error parsing model row: #{e.message}")
              next
            end
          end
        rescue => e
          logger.warn("Error parsing models table: #{e.message}")
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

    def fetch_pricing
      doc = fetch_html(MODELS_URL, "pricing page")
      return {} unless doc

      pricing_data = {}

      # Parse pricing table
      doc.css('table').each do |table|
        begin
          rows = table.css('tr')
          next if rows.empty?

          # Get header to determine column positions
          headers = rows.first.css('th, td').map { |h| safe_text(h).downcase }
          next unless headers.any? { |h| h.include?('input') || h.include?('output') }

          rows[1..-1]&.each do |row|
            begin
              cells = row.css('td')
              next if cells.empty?

              model_name = safe_text(cells[0])
              next if model_name.empty? || header_row?(model_name)

              # Extract API name from model name
              api_name = extract_api_name_from_model_name(model_name)
              next unless api_name

              pricing_info = extract_pricing_info(cells)
              pricing_data[api_name] = pricing_info unless pricing_info.empty?
            rescue => e
              logger.warn("Error parsing pricing row: #{e.message}")
              next
            end
          end
        rescue => e
          logger.warn("Error parsing pricing table: #{e.message}")
          next
        end
      end

      logger.info("Extracted pricing for #{pricing_data.size} models")
      pricing_data
    rescue => e
      logger.error("Error in fetch_pricing: #{e.class} - #{e.message}")
      {}
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

    def extract_pricing_info(cells)
      pricing = {}

      # Extract pricing based on cell position
      # Format: Model, Input, Output, Cached Read, Cached Write
      if cells.length >= 3
        input_price = extract_price(safe_text(cells[1]))
        output_price = extract_price(safe_text(cells[2]))

        pricing[:input_price] = input_price if input_price
        pricing[:output_price] = output_price if output_price

        # Cached pricing if available
        if cells.length >= 4
          cached_read = extract_price(safe_text(cells[3]))
          pricing[:cache_hit_price] = cached_read if cached_read
        end

        if cells.length >= 5
          cached_write = extract_price(safe_text(cells[4]))
          pricing[:cache_write_price] = cached_write if cached_write
        end
      end

      pricing.compact
    rescue => e
      logger.warn("Error extracting pricing info: #{e.message}")
      {}
    end

    def safe_text(element)
      return '' if element.nil?
      element.text.to_s.strip.gsub(/\s+/, ' ')
    rescue => e
      logger.warn("Error extracting text: #{e.message}")
      ''
    end

    def header_row?(text)
      text_lower = text.downcase
      text_lower.include?('model') && text_lower.include?('id')
    end

    def extract_price(text)
      return nil if text.nil? || text.empty? || text == '-'

      # Extract numeric value from strings like "$3.00", "Free", "$15.00"
      cleaned = text.gsub(/[\s,]/, '')
      if cleaned.downcase == 'free'
        return 0.0
      end

      match = cleaned.match(/\$?([\d.]+)/)
      return nil unless match

      price = match[1].to_f
      price > 0 ? price : nil
    rescue => e
      logger.warn("Error extracting price from '#{text}': #{e.message}")
      nil
    end

    def extract_api_name_from_model_name(model_name)
      return nil if model_name.nil? || model_name.empty?

      # Map model names to API names based on the Zen docs
      name_mapping = {
        'GPT 5' => 'gpt-5',
        'GPT 5 Codex' => 'gpt-5-codex',
        'Claude Sonnet 4.5' => 'claude-sonnet-4-5',
        'Claude Sonnet 4' => 'claude-sonnet-4',
        'Claude Haiku 3.5' => 'claude-3-5-haiku',
        'Claude Opus 4.1' => 'claude-opus-4-1',
        'Qwen3 Coder 480B' => 'qwen3-coder',
        'Grok Code Fast 1' => 'grok-code',
        'Kimi K2' => 'kimi-k2'
      }

      name_mapping[model_name.strip] || model_name.downcase.gsub(/\s+/, '-').gsub(/[^\w-]/, '')
    rescue => e
      logger.warn("Error extracting API name from '#{model_name}': #{e.message}")
      nil
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.