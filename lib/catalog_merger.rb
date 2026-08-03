require 'json'
require 'open3'
require 'fileutils'
require_relative 'colored_logger'
require_relative 'provider_canonicalizer'

# Builds catalog/<provider>/models.jsonl by overlaying input_sources/external
# data onto input_sources/native data, in priority order.
#
# Priority order (highest first): input_sources/native/<provider>, then each
# configured external source. Native data is only trusted if its models.jsonl
# was committed within FRESHNESS_DAYS; otherwise it's treated as broken and
# skipped, so the next source in priority order becomes the base for that
# provider.
#
# spider-rs has no real per-provider grouping (see Providers::SpiderRs), so it
# isn't part of the normal priority chain: after every other source is merged,
# each spider-rs model is folded in only if its id exactly matches exactly one
# already-known provider bucket. Anything that matches zero or multiple
# providers is dropped rather than guessed at or dumped in its own bucket.
#
# catalog/<provider>/models.jsonl is this class's output -- CatalogUpdater
# only renders it into markdown/HTML, it does not produce it.
class CatalogMerger
  FRESHNESS_DAYS = 30

  NATIVE_DIR = 'input_sources/native'
  EXTERNAL_DIR = 'input_sources/external'
  CATALOG_DIR = 'catalog'

  # Priority order among external sources, highest first. spider-rs is handled
  # separately (see class comment) and deliberately excluded from this list.
  EXTERNAL_SOURCE_PRIORITY = %w[opencode-cli truefoundry].freeze

  SPIDER_RS_SOURCE = 'spider-rs'

  def self.merge_catalogs(logger: ColoredLogger.new(STDOUT))
    new(logger: logger).merge_catalogs
  end

  def initialize(logger: ColoredLogger.new(STDOUT))
    @logger = logger
  end

  def merge_catalogs
    merged_by_provider = {}

    all_provider_names.each do |provider|
      models = merge_provider(provider)
      merged_by_provider[provider] = models unless models.empty?
    end

    fold_in_spider_rs(merged_by_provider)

    merged_by_provider.each do |provider, models|
      next if models.empty?

      write_catalog(provider, models)
      @logger.info("Merged #{models.size} models for #{provider}")
    end
  end

  private

  def all_provider_names
    names = native_provider_names + external_provider_names
    names.map { |name| ProviderCanonicalizer.canonicalize(name) }.uniq.sort
  end

  def native_provider_names
    Dir.glob("#{NATIVE_DIR}/*")
       .select { |d| File.directory?(d) }
       .map { |d| File.basename(d) }
  end

  def external_provider_names
    EXTERNAL_SOURCE_PRIORITY.flat_map do |source|
      Dir.glob("#{EXTERNAL_DIR}/#{source}/*")
         .select { |d| File.directory?(d) }
         .map { |d| File.basename(d) }
    end
  end

  # A canonical provider name (e.g. "mistral-ai") may correspond to several
  # on-disk spellings for a given source (e.g. truefoundry's "mistral-ai" or
  # opencode-cli's "mistral"). Returns every on-disk name under `source` that
  # canonicalizes to `canonical_provider`.
  def source_dir_names_for(source, canonical_provider)
    base = source == 'native' ? NATIVE_DIR : "#{EXTERNAL_DIR}/#{source}"
    Dir.glob("#{base}/*")
       .select { |d| File.directory?(d) }
       .map { |d| File.basename(d) }
       .select { |name| ProviderCanonicalizer.canonicalize(name) == canonical_provider }
  end

  def merge_provider(canonical_provider)
    base_source, base_models = base_for(canonical_provider)
    merged = {}
    base_models.each { |m| merged[m['id']] = m }

    source_chain_after(base_source).each do |source|
      models = models_for_source(source, canonical_provider)
      models.each do |model|
        id = model['id']
        if merged.key?(id)
          merged[id] = fill_gaps(merged[id], model)
        else
          merged[id] = model
        end
      end
    end

    merged.values.sort_by { |m| m['name'].to_s }
  end

  def models_for_source(source, canonical_provider)
    source_dir_names_for(source, canonical_provider).flat_map do |dir_name|
      base = source == 'native' ? NATIVE_DIR : "#{EXTERNAL_DIR}/#{source}"
      read_models("#{base}/#{dir_name}/models.jsonl")
    end
  end

  # Returns [source_name, models] for whichever source should seed this provider:
  # native if fresh, else the highest-priority external source that has data.
  def base_for(canonical_provider)
    native_dirs = source_dir_names_for('native', canonical_provider)
    fresh_native_dir = native_dirs.find { |dir| fresh?("#{NATIVE_DIR}/#{dir}/models.jsonl") }

    if fresh_native_dir
      return ['native', read_models("#{NATIVE_DIR}/#{fresh_native_dir}/models.jsonl")]
    end

    EXTERNAL_SOURCE_PRIORITY.each do |source|
      models = models_for_source(source, canonical_provider)
      return [source, models] unless models.empty?
    end

    ['native', native_dirs.flat_map { |dir| read_models("#{NATIVE_DIR}/#{dir}/models.jsonl") }]
  end

  def source_chain_after(base_source)
    return EXTERNAL_SOURCE_PRIORITY if base_source == 'native'

    index = EXTERNAL_SOURCE_PRIORITY.index(base_source) || -1
    EXTERNAL_SOURCE_PRIORITY[(index + 1)..] || []
  end

  def fresh?(path)
    timestamp = last_commit_timestamp(path)
    return true if timestamp.nil? # untracked/new file: assume fresh rather than discarding it

    age_days = (Time.now - Time.at(timestamp)) / 86_400
    age_days <= FRESHNESS_DAYS
  end

  def last_commit_timestamp(path)
    stdout, status = Open3.capture2('git', 'log', '-1', '--format=%ct', '--', path)
    return nil unless status.success?

    stdout.strip.empty? ? nil : stdout.strip.to_i
  rescue Errno::ENOENT
    nil
  end

  def read_models(path)
    return [] unless File.exist?(path)

    models = []
    File.foreach(path) do |line|
      line.strip!
      next if line.empty?

      begin
        models << JSON.parse(line)
      rescue JSON::ParserError => e
        @logger.warn("Skipping malformed line in #{path}: #{e.message}")
      end
    end
    models
  end

  # Fills nil/missing fields on `existing` from `candidate`; never overwrites
  # a field `existing` already has, and never removes fields unique to `existing`.
  def fill_gaps(existing, candidate)
    merged = existing.dup
    candidate.each do |key, value|
      next if merged.key?(key) && !merged[key].nil?

      merged[key] = value
    end
    merged
  end

  # spider-rs has no trustworthy provider grouping of its own. A model is
  # folded into `merged_by_provider` only when its id exactly matches exactly
  # one provider's existing model set; anything matching zero or multiple
  # providers is dropped (counted and logged, not silently discarded).
  def fold_in_spider_rs(merged_by_provider)
    spider_models = read_models("#{EXTERNAL_DIR}/#{SPIDER_RS_SOURCE}/models.jsonl")
    return if spider_models.empty?

    id_to_providers = Hash.new { |h, k| h[k] = [] }
    merged_by_provider.each do |provider, models|
      models.each { |m| id_to_providers[m['id']] << provider }
    end

    matched = 0
    dropped = 0

    spider_models.each do |model|
      candidates = id_to_providers[model['id']].uniq
      if candidates.size == 1
        provider = candidates.first
        index = merged_by_provider[provider].index { |m| m['id'] == model['id'] }
        merged_by_provider[provider][index] = fill_gaps(merged_by_provider[provider][index], model)
        matched += 1
      else
        dropped += 1
      end
    end

    @logger.info("spider-rs: folded #{matched} models into existing providers, dropped #{dropped} with zero or ambiguous provider matches")
  end

  def write_catalog(provider, models)
    dir = "#{CATALOG_DIR}/#{provider}"
    FileUtils.mkdir_p(dir)
    File.write("#{dir}/models.jsonl", models.map { |m| JSON.generate(m) }.join("\n") + "\n")
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
