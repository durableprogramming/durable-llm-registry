require 'faraday'
require_relative '../colored_logger'
require_relative '../http_cache'

module Fetchers
  class Anthropic
    # The models overview is served as Markdown. Its tables are transposed:
    # the first column lists feature labels (Claude API ID, Pricing, Context
    # window, ...) and each subsequent column is a model. We parse those tables
    # directly; no separate pricing fetch is needed since pricing lives inline.
    MODELS_URL = 'https://platform.claude.com/docs/en/about-claude/models/overview.md'

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
      markdown = fetch_text(MODELS_URL, "models overview page")
      return [] if markdown.nil? || markdown.strip.empty?

      models = parse_models(markdown)
      logger.info("Successfully fetched #{models.size} models")
      models
    rescue => e
      logger.error("Failed to fetch Anthropic data: #{e.class} - #{e.message}")
      []
    end

    private

    # Walk the markdown, find each model table (a transposed table whose first
    # column header is "Feature" and that carries a "Claude API ID" row), and
    # build one model hash per data column.
    def parse_models(markdown)
      models = []

      each_table(markdown) do |header, rows|
        # header[0] is the "Feature" label; header[1..] are model display names.
        model_names = header[1..] || []
        next if model_names.empty?

        # Index rows by their feature label for direct lookup. Labels carry
        # markdown bold markers and footnote suffixes (e.g. "**Pricing**<sup>1
        # </sup>"), so normalize before keying.
        by_label = {}
        rows.each { |cells| by_label[normalize_label(cells[0])] = cells }

        id_row = by_label['claude api id']
        next unless id_row # not a model table (e.g. unrelated tables)

        model_names.each_with_index do |raw_name, col|
          cell = col + 1 # data columns start at index 1

          api_name = clean_id(id_row[cell])
          next unless valid_api_name?(api_name)

          name = clean_model_name(raw_name)
          next if name.empty?

          input_price, output_price = parse_pricing_cell(value(by_label, 'pricing', cell))

          model = {
            name: name,
            api_name: api_name,
            bedrock_name: clean_id(value(by_label, 'aws bedrock id', cell)),
            vertex_name: clean_id(value(by_label, 'vertex ai id', cell)),
            context_window: parse_token_count(value(by_label, 'context window', cell)),
            max_output_tokens: parse_token_count(value(by_label, 'max output', cell))
          }
          model[:input_price] = input_price if input_price
          model[:output_price] = output_price if output_price

          models << model.compact
        end
      end

      models.uniq { |m| m[:api_name] }
    end

    # Yield [header_cells, data_rows] for each markdown table in the document.
    def each_table(markdown)
      lines = markdown.lines.map(&:rstrip)
      i = 0
      while i < lines.length
        line = lines[i]
        # A table starts at a pipe row immediately followed by a separator row.
        if table_row?(line) && i + 1 < lines.length && separator_row?(lines[i + 1])
          header = split_markdown_row(line)
          rows = []
          j = i + 2
          while j < lines.length && table_row?(lines[j])
            rows << split_markdown_row(lines[j]) unless separator_row?(lines[j])
            j += 1
          end
          yield header, rows
          i = j
        else
          i += 1
        end
      end
    end

    # Normalize a feature-label cell to a bare lowercase key, dropping bold
    # markers, footnote <sup> markers, and any markdown link wrapper.
    def normalize_label(text)
      return '' if text.nil?
      text.gsub(/<sup>.*?<\/sup>/, '')
          .gsub(/<[^>]+>/, '')
          .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')
          .gsub(/[`*]/, '')
          .downcase
          .strip
    end

    def value(by_label, label, cell)
      row = by_label[label]
      row && row[cell]
    end

    def table_row?(line)
      line.lstrip.start_with?('|')
    end

    def separator_row?(line)
      line.match?(/\|/) && line.gsub(/[\s|:-]/, '').empty?
    end

    # Split a markdown table row into cells, dropping the empty leading/trailing
    # cells produced by the surrounding pipes.
    def split_markdown_row(line)
      parts = line.strip.split('|')
      parts.shift if parts.first.to_s.strip.empty?
      parts.pop if parts.last.to_s.strip.empty?
      parts.map { |c| c.strip }
    end

    # Strip markdown emphasis/bold markers and trailing footnote markers from a
    # cell that should contain a bare API id, e.g. "**claude-opus-4-8**" or
    # "anthropic.claude-opus-4-8<sup>3</sup>".
    def clean_id(text)
      return '' if text.nil?
      text.gsub(/<sup>.*?<\/sup>/, '')
          .gsub(/<[^>]+>/, '')
          .gsub(/[`*]/, '')
          .strip
    end

    # Strip bold markers and trailing annotations like "(deprecated)" from a
    # model display name cell.
    def clean_model_name(text)
      return '' if text.nil?
      text.gsub(/[`*]/, '')
          .sub(/\s*\(deprecated\)\s*$/i, '')
          .strip
    end

    # Parse a pricing cell such as "\$5 / input MTok<br/>\$25 / output MTok"
    # into [input_price, output_price]. Either may be nil if not present.
    def parse_pricing_cell(text)
      return [nil, nil] if text.nil? || text.empty?

      # Split the combined "input / output per MTok" form, e.g.
      # "$10 / $50 per MTok (input / output)".
      if text.match?(/per mtok.*input.*output/i)
        nums = text.scan(/\$?\\?\$?\s*([\d.]+)/).flatten.map(&:to_f).reject(&:zero?)
        return [nums[0], nums[1]] if nums.length >= 2
      end

      input = price_for_label(text, 'input')
      output = price_for_label(text, 'output')
      [input, output]
    end

    # Pull the price associated with a labeled segment ("input" or "output")
    # from a pricing cell. Handles "$5 / input MTok" and escaped "\$5".
    def price_for_label(text, label)
      text.split(/<br\s*\/?>/i).each do |segment|
        next unless segment.downcase.include?(label)
        m = segment.match(/\\?\$\s*([\d.]+)/)
        return m[1].to_f if m && m[1].to_f > 0
      end
      nil
    end

    # Parse a token-count cell like "1M tokens", "200k tokens", or one wrapped
    # in "<Tooltip ...>1M tokens</Tooltip>" into an integer.
    def parse_token_count(text)
      return nil if text.nil? || text.empty?
      stripped = text.gsub(/<[^>]+>/, ' ')
      m = stripped.match(/([\d.]+)\s*([mMkK])\b/)
      return nil unless m

      num = m[1].to_f
      case m[2].downcase
      when 'm' then (num * 1_000_000).to_i
      when 'k' then (num * 1_000).to_i
      end
    end

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

    def valid_api_name?(api_name)
      return false if api_name.nil? || api_name.empty?
      api_name.match?(/^claude-[\w-]+$/) && !api_name.match?(/\s/)
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
