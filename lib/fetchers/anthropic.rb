require 'nokogiri'
require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class Anthropic
    MODELS_URL = 'https://docs.claude.com/en/docs/about-claude/models/overview'
    PRICING_URL = 'https://platform.claude.com/docs/en/about-claude/pricing.md'

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
      pricing = fetch_pricing

      # The models page is a client-rendered app with no scrapable table, so the
      # pricing Markdown is the canonical model list. If the HTML models page is
      # ever scrapable again it supplies extra metadata (Bedrock/Vertex names);
      # otherwise we synthesize the list from the pricing table.
      models = fetch_models
      if models.empty?
        logger.info("Models page not scrapable; deriving models from pricing table")
        models = models_from_pricing(pricing)
      end

      return [] if models.empty?

      # Combine models and pricing data. Model api_names may carry a date suffix
      # (claude-opus-4-8-20251101) while pricing keys are the undated
      # family+version (claude-opus-4-8), so match exactly first and fall back to
      # a prefix match against the pricing keys.
      combined = models.map do |model|
        next unless model[:api_name]
        prices = pricing_for(pricing, model[:api_name])
        model.merge(prices || {})
      end.compact

      logger.info("Successfully fetched #{combined.size} models")
      combined
    rescue => e
      logger.error("Failed to fetch Anthropic data: #{e.class} - #{e.message}")
      []
    end

    private

    # Synthesize the model list from the pricing keys when the HTML models page
    # is unavailable. The pricing api_name doubles as the model id.
    def models_from_pricing(pricing)
      names = @pricing_names || {}
      pricing.keys.map do |api_name|
        { name: names[api_name] || display_name_for(api_name), api_name: api_name }
      end
    end

    # Best-effort human label for a synthesized api_name, e.g. "claude-opus-4-8"
    # => "Claude Opus 4 8". Used only if the pricing table did not record a name.
    def display_name_for(api_name)
      api_name.split('-').map(&:capitalize).join(' ')
    end

    # Find the pricing entry for a model api_name. Tries an exact key match,
    # then the longest pricing key that the api_name starts with (to bridge the
    # dated id -> undated pricing-key gap).
    def pricing_for(pricing, api_name)
      return pricing[api_name] if pricing.key?(api_name)

      candidates = pricing.keys.select { |key| api_name.start_with?("#{key}-") }
      best = candidates.max_by(&:length)
      best ? pricing[best] : nil
    end

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
      markdown = fetch_text(PRICING_URL, "pricing page")
      parse_pricing(markdown)
    end

    # Parse the Anthropic pricing Markdown into a hash of api_name => price hash.
    def parse_pricing(markdown)
      return {} if markdown.nil? || markdown.strip.empty?

      pricing_data = {}
      # Remember the display name for each api_name so models synthesized from
      # pricing keep their proper "Claude Opus 4.8" labels.
      @pricing_names = {}

      # The pricing page is served as Markdown. Find the model pricing table by
      # its header row, then parse each model row from it.
      table_rows = pricing_table_rows(markdown)

      table_rows.each do |cells|
        begin
          model_name = clean_model_name(cells[0])
          next if model_name.nil? || model_name.empty? || header_row?(model_name)

          api_name = extract_api_name_from_text(model_name)
          next unless api_name && valid_api_name?(api_name)

          pricing_info = extract_markdown_pricing(cells)
          next if pricing_info.empty?

          pricing_data[api_name] = pricing_info
          @pricing_names[api_name] = model_name
        rescue => e
          logger.warn("Error parsing pricing row: #{e.message}")
          next
        end
      end

      logger.info("Extracted pricing for #{pricing_data.size} models")
      pricing_data
    rescue => e
      logger.error("Error in fetch_pricing: #{e.class} - #{e.message}")
      {}
    end

    # Locate the model pricing table in the markdown document and return its
    # data rows as arrays of cleaned cell strings. The table has the columns:
    # Model | Base Input Tokens | 5m Cache Writes | 1h Cache Writes |
    # Cache Hits & Refreshes | Output Tokens
    def pricing_table_rows(markdown)
      lines = markdown.lines.map(&:rstrip)

      header_index = lines.index do |line|
        line.match?(/\|/) &&
          line.match?(/base input/i) &&
          line.match?(/output/i)
      end
      return [] unless header_index

      rows = []
      # Skip the header line and its separator (|---|---|) line.
      lines[(header_index + 1)..-1].to_a.each do |line|
        break unless line.include?('|')
        next if separator_row?(line)

        cells = split_markdown_row(line)
        next if cells.empty?
        rows << cells
      end

      rows
    end

    # Strip trailing annotations from a model name cell. The pricing table
    # appends markdown links like "([deprecated](/docs/.../model-deprecations))"
    # whose URLs would otherwise trip up name matching.
    def clean_model_name(text)
      return '' if text.nil?
      text.sub(/\s*\(\[.*\]\(.*\)\).*$/, '').strip
    end

    def separator_row?(line)
      stripped = line.gsub(/[\s|:-]/, '')
      stripped.empty?
    end

    # Split a markdown table row into cells, dropping the leading/trailing
    # empty cells produced by the surrounding pipes and normalizing whitespace.
    def split_markdown_row(line)
      parts = line.split('|')
      parts.shift if parts.first.to_s.strip.empty?
      parts.pop if parts.last.to_s.strip.empty?
      parts.map { |c| c.strip.gsub(/\s+/, ' ') }
    end

    # Extract input/cache/output prices from a markdown pricing row.
    # Cell layout: [name, base_input, 5m_cache_write, 1h_cache_write,
    #               cache_hit, output]
    def extract_markdown_pricing(cells)
      pricing = {}

      input_price = extract_price(cells[1])
      cache_write_price = extract_price(cells[2])
      cache_hit_price = extract_price(cells[4])
      output_price = extract_price(cells[-1])

      pricing[:input_price] = input_price if input_price
      pricing[:cache_write_price] = cache_write_price if cache_write_price
      pricing[:cache_hit_price] = cache_hit_price if cache_hit_price
      pricing[:output_price] = output_price if output_price

      pricing.compact
    rescue => e
      logger.warn("Error extracting markdown pricing: #{e.message}")
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

    # Fetch a URL and return the raw response body as a string, with retry on
    # timeout. Used for endpoints served as plain text / Markdown rather than HTML.
    def fetch_text(url, description)
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

        body
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


       # Extract model family and version dynamically. Match either the family
       # name followed by a version (e.g. "Opus 4.8", "Fable 5") or a version
       # followed by the family name (e.g. "3.5 Haiku").
        families = '(opus|sonnet|haiku|fable|mythos)'
        match = text_lower.match(/#{families}\s*\d+(?:\.\d+)?/) ||
                text_lower.match(/\d+(?:\.\d+)?\s*#{families}/)
        return nil unless match

        family = match[1]  # families regex has a single capture group
        version_match = text_lower.match(/\d+(?:\.\d+)?/)
        return nil unless version_match
        version = version_match[0]

      # Validate version format
      return nil unless version.match?(/^\d+(\.\d+)?$/)

      version_num = version.to_f
      return nil if version_num <= 0

      # Determine naming convention based on version
      if version_num >= 4.0
        # New format: claude-{family}-{major}-{minor}, e.g. "Claude Opus 4.8"
        # becomes "claude-opus-4-8" to match the dated API ids on the models
        # page (claude-opus-4-8-YYYYMMDD). A bare major like "4" stays as "4".
        version_clean = version.sub(/\.0$/, '').tr('.', '-')
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