require 'nokogiri'
require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class Perplexity
    MODELS_URL = 'https://docs.perplexity.ai/getting-started/models'
    PRICING_URL = 'https://docs.perplexity.ai/getting-started/pricing'

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
      logger.error("Failed to fetch Perplexity data: #{e.class} - #{e.message}")
      []
    end

    private

    def fetch_models
      doc = fetch_html(MODELS_URL, "models page")
      return [] unless doc

      models = []

      # Look for links with model cards
      doc.css('a[href*="models/sonar"]').each do |link|
        begin
          href = link['href']
          next unless href

          # Extract API name from href
          api_name_match = href.match(/models\/(sonar[-\w]*)/)
          next unless api_name_match

          api_name = api_name_match[1]
          next unless valid_api_name?(api_name)

          # Extract model name from the div with class containing "font-semibold"
          model_name_div = link.css('div[class*="font-semibold"]').first
          next unless model_name_div

          model_name = safe_text(model_name_div)

          models << {
            name: model_name,
            api_name: api_name
          }
        rescue => e
          logger.warn("Error parsing model link: #{e.message}")
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
      doc = fetch_html(PRICING_URL, "pricing page")
      return {} unless doc

      pricing_data = {}

      # Parse pricing table
      doc.css('table').each do |table|
        begin
          rows = table.css('tr')
          next if rows.empty?

          # Get headers
          headers = rows.first.css('th, td').map { |h| safe_text(h).downcase }
          next if headers.empty?

          # Skip tables that don't look like pricing tables
          next unless headers.any? { |h| h.match?(/model|input|output|token/i) }

          rows[1..-1]&.each do |row|
            begin
              cells = row.css('td')
              next if cells.empty?

              model_name = safe_text(cells[0])
              next if model_name.empty? || header_row?(model_name)

              # Extract API name from model name
              api_name = extract_api_name_from_text(model_name)
              next unless api_name && valid_api_name?(api_name)

              pricing_info = extract_pricing_info(cells, headers)
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

    def extract_pricing_info(cells, headers)
      pricing = {}

      # Map headers to keys
      header_map = {
        'input tokens ($/1m)' => :input_price,
        'output tokens ($/1m)' => :output_price,
        'citation tokens ($/1m)' => :citation_price,
        'search queries ($/1k)' => :search_query_price,
        'reasoning tokens ($/1m)' => :reasoning_price
      }

      cells.each_with_index do |cell, idx|
        next if idx == 0 # Skip model name column

        price = extract_price(safe_text(cell))
        next unless price

        header = headers[idx].to_s.downcase
        key = header_map[header] || determine_price_key(header, idx, cells.length)
        pricing[key] = price if key
      end

      pricing.compact
    rescue => e
      logger.warn("Error extracting pricing info: #{e.message}")
      {}
    end

    def determine_price_key(header, index, total_cells)
      return :input_price if header.match?(/input/i)
      return :output_price if header.match?(/output/i)
      return :citation_price if header.match?(/citation/i)
      return :search_query_price if header.match?(/search.*quer/i)
      return :reasoning_price if header.match?(/reasoning/i)

      # Fallback to position-based heuristics
      case index
      when 1 then :input_price
      when 2 then :output_price
      when 3 then :citation_price
      when 4 then :search_query_price
      when 5 then :reasoning_price
      else nil
      end
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
      text_lower.include?('model') ||
        text_lower == 'feature'
    end

    def valid_api_name?(api_name)
      return false if api_name.nil? || api_name.empty?
      api_name.match?(/^sonar/) && !api_name.match?(/\s/)
    end

    def extract_price(text)
      return nil if text.nil? || text.empty? || text == '-'

      # Extract numeric value from strings like "$1", "$3", etc.
      cleaned = text.gsub(/[\s,]/, '')
      match = cleaned.match(/\$?([\d.]+)/)

      return nil unless match

      price = match[1].to_f
      price > 0 ? price : nil
    rescue => e
      logger.warn("Error extracting price from '#{text}': #{e.message}")
      nil
    end

    def extract_api_name_from_text(text)
      return nil if text.nil? || text.empty?

      text_lower = text.downcase.strip

      # First, check if it's already a valid API name
      return text.strip if text.match?(/^sonar/)

      # Extract from model names like "Sonar", "Sonar Pro", etc.
      case text_lower
      when /sonar deep research/i
        'sonar-deep-research'
      when /sonar reasoning pro/i
        'sonar-reasoning-pro'
      when /sonar reasoning/i
        'sonar-reasoning'
      when /sonar pro/i
        'sonar-pro'
      when /sonar/i
        'sonar'
      else
        nil
      end
    end

    def extract_api_name(model_name)
      extract_api_name_from_text(model_name)
    end

    def extract_model_name_from_link(text)
      return nil if text.nil? || text.empty?

      # Link text format: "sonar Sonar Lightweight, cost-effective search model with grounding."
      # We want "Sonar" or "Sonar Pro" etc.
      parts = text.strip.split
      return nil if parts.empty?

      # Skip the api_name part and take the next words until we hit a description
      model_parts = []
      parts[1..-1].each do |part|
        break if part.match?(/^(Lightweight|Advanced|Fast|Precise|Expert-level)/i)
        model_parts << part
      end

      model_parts.join(' ').strip
    rescue => e
      logger.warn("Error extracting model name from link '#{text}': #{e.message}")
      nil
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.