 require 'stellar/erb'
 require 'json'
 require_relative 'colored_logger'

  class CatalogUpdater
    def self.update_catalogs
      logger = ColoredLogger.new(STDOUT)
      logger.info("Starting catalog update process...")
      md_template_path = 'templates/catalog.md.erb'
      html_index_template_path = 'templates/index.html.erb'
      html_provider_template_path = 'templates/provider_index.html.erb'
      return unless File.exist?(md_template_path) && File.exist?(html_index_template_path) && File.exist?(html_provider_template_path)

      providers = []
      Dir.glob('catalog/*').select { |d| File.directory?(d) }.each do |dir|
        provider = File.basename(dir)
        providers << provider
        logger.info("Processing provider: #{provider}")
        models_file = File.join(dir, 'models.jsonl')
        next unless File.exist?(models_file)
        models = []
        File.foreach(models_file) do |line|
          line.strip!
          next if line.empty?
          models << JSON.parse(line)
        end
        models.sort_by! { |m| m['name'] }
        logger.info("Loaded #{models.size} models for #{provider}")

        # Render Markdown catalog
        catalog_content = Stellar::Erb.render(md_template_path, provider: provider, models: models)
        catalog_file = File.join(dir, 'catalog.md')
        File.write(catalog_file, catalog_content)
        logger.info("Updated catalog.md for #{provider}")

        # Render HTML provider index
        html_provider_content = Stellar::Erb.render(html_provider_template_path, provider: provider, models: models)
        html_provider_file = File.join(dir, 'index.html')
        File.write(html_provider_file, html_provider_content)
        logger.info("Updated index.html for #{provider}")
      end

      # Render main HTML index
      providers.sort!
      html_index_content = Stellar::Erb.render(html_index_template_path, providers: providers)
      html_index_file = File.join('catalog', 'index.html')
      File.write(html_index_file, html_index_content)
      logger.info("Updated main index.html")

      # Write providers.json
      providers_json_file = File.join('catalog', 'providers.json')
      File.write(providers_json_file, JSON.pretty_generate(providers))
      logger.info("Updated providers.json")

      logger.info("Catalog update process completed")
    end
  end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.