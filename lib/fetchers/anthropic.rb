require 'nokogiri'
require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class Anthropic
    MODELS_URL = 'https://docs.claude.com/en/docs/about-claude/models/overview'
    PRICING_URL = 'https://docs.claude.com/en/docs/about-claude/pricing'

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
      logger.error("Failed to fetch Anthropic data: #{e.class} - #{e.message}")
      []
    end

    private

    def fetch_models
      doc = fetch_html(MODELS_URL, "models page")
      return [] unless doc

      models = []

      # Parse model tables - targeting table rows
      doc.css('table tr').each do |row|
        begin
          cells = row.css('td')
          next if cells.empty? || cells.length < 2

          model_name = safe_text(cells[0])
          api_name = safe_text(cells[1])

          # Skip header rows and empty entries
          next if model_name.empty? || api_name.empty?
          next if header_row?(model_name)
          next unless valid_api_name?(api_name)

          models << {
            name: model_name,
            api_name: api_name,
            bedrock_name: safe_text(cells[2]),
            vertex_name: safe_text(cells[3])
          }.compact
        rescue => e
          logger.warn("Error parsing model row: #{e.message}")
          next
        end
      end

      # Also try to extract from heading sections as fallback
      doc.css('h2, h3').each do |heading|
        begin
          text = safe_text(heading)
          next unless text.match?(/claude/i) && text.match?(/\d+/)

          api_name = extract_api_name(heading)
          next unless api_name && valid_api_name?(api_name)

          models << {
            name: text,
            api_name: api_name
          }
        rescue => e
          logger.warn("Error parsing heading: #{e.message}")
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

          # Get header to determine column positions
          headers = rows.first.css('th, td').map { |h| safe_text(h).downcase }
          next if headers.empty?

          # Skip tables that don't look like pricing tables
          next unless headers.any? { |h| h.match?(/model|price|token/i) }

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

        if doc.nil? || doc.children.empty? || doc.errors.any?
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

      # Try to intelligently extract pricing based on cell position
      cells.each_with_index do |cell, idx|
        next if idx == 0 # Skip model name column

        price = extract_price(safe_text(cell))
        next unless price

        # Determine price type based on header or position
        header = headers[idx].to_s.downcase
        key = determine_price_key(header, idx, cells.length)
        pricing[key] = price if key
      end

      pricing.compact
    rescue => e
      logger.warn("Error extracting pricing info: #{e.message}")
      {}
    end

    def determine_price_key(header, index, total_cells)
      return :input_price if header.match?(/input|base.*input/i)
      return :output_price if header.match?(/output/i)
      return :cache_write_price if header.match?(/cache.*write|write.*cache/i)
      return :cache_hit_price if header.match?(/cache.*hit|hit.*cache|refresh/i)

       # Fallback to position-based heuristics
       case index
       when 1 then :input_price
       when 2 then :cache_write_price
       when total_cells - 2 then :cache_hit_price
       when total_cells - 1 then :output_price
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
        text_lower.include?('name') ||
        text_lower.include?('api') ||
        text_lower == 'feature'
    end

    def valid_api_name?(api_name)
      return false if api_name.nil? || api_name.empty?
      api_name.match?(/^claude-[\w-]+$/) && !api_name.match?(/\s/)
    end

    def extract_price(text)
      return nil if text.nil? || text.empty?

      # Extract numeric value from strings like "$3 / MTok", "3.00", "$15.00"
      # Handle various formats: with/without $, with/without spaces
      cleaned = text.gsub(/[\s,]/, '')
      match = cleaned.match(/\$?(-?[\d.]+)/)

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
       return text.strip if valid_api_name?(text.strip)


       # Extract model family and version dynamically
        # Match pattern: either (opus|sonnet|haiku) followed by version number, or version followed by (opus|sonnet|haiku)
        match = text_lower.match(/(opus|sonnet|haiku).*\d+(?:\.\d+)?/) || text_lower.match(/\d+(?:\.\d+)?\s*(opus|sonnet|haiku)/)
        return nil unless match

        family = match[1] || match[3]  # family could be in either capture group
        version_match = text_lower.match(/\d+(?:\.\d+)?/)
        return nil unless version_match
        version = version_match[0]

      # Validate version format
      return nil unless version.match?(/^\d+(\.\d+)?$/)

      version_num = version.to_f
      return nil if version_num <= 0

      # Determine naming convention based on version
      if version_num >= 4.0
        # New format: claude-{family}-{version}
        version_clean = version.sub(/\.0$/, '')
        "claude-#{family}-#{version_clean}"
      else
        # Old format: claude-3-{family} or claude-3-5-{family} or claude-3-7-{family} style
        if version_num == 3.0
          "claude-3-#{family}"
        elsif version_num == 3.5
          "claude-3-5-#{family}"
        elsif version_num >= 3.0
          major, minor = version.split('.')
          "claude-#{major}-#{minor}-#{family}"
        else
          # Handle even older versions generically
          major = version.split('.').first
          "claude-#{major}-#{family}"
        end
      end
    rescue => e
      logger.warn("Error extracting API name from '#{text}': #{e.message}")
      nil
    end

    def extract_api_name(element)
      return nil if element.nil?

      # Look for code blocks near the heading that might contain API names
      sibling = element.next_element
      depth = 0
      max_depth = 10 # Prevent infinite loops

      while sibling && depth < max_depth
        begin
          # Check if this sibling contains code with an API name
          if sibling.name == 'code'
            code_text = sibling.text&.strip
            if code_text && code_text.match?(/^claude-[\w-]+$/) && valid_api_name?(code_text)
              return code_text
            end
          elsif sibling.css('code').any?
            code_element = sibling.css('code').first
            code_text = code_element&.text&.strip
            if code_text && code_text.match?(/^claude-[\w-]+$/) && valid_api_name?(code_text)
              return code_text
            end
          end

          # Stop if we hit another heading
          break if sibling.name&.match?(/^h[1-6]$/i)

          sibling = sibling.next_element
          depth += 1
        rescue => e
          logger.warn("Error traversing siblings: #{e.message}")
          break
        end
      end

      nil
    rescue => e
      logger.warn("Error extracting API name from element: #{e.message}")
      nil
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.