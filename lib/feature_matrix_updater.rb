require_relative 'provider_registry'

module Providers
  class FeatureMatrixUpdater
    PROVIDERS = Registry.new.all

    def self.generate_feature_matrix
      matrix = []

      PROVIDERS.each do |provider_class|
        provider = provider_class.new
        provider_name = provider_class.name.split('::').last

        matrix << {
          provider: provider_name,
          api_specs: provider.can_pull_api_specs?,
          model_info: provider.can_pull_model_info?,
          pricing: provider.can_pull_pricing?
        }
      end

      matrix
    end

    def self.generate_markdown
      matrix = generate_feature_matrix

      markdown = "# Provider Feature Matrix\n\n"
      markdown += "This matrix shows which providers support dynamic pulling of API specifications, model information, and pricing data.\n\n"
      markdown += "| Provider | API Specs | Model Info | Pricing |\n"
      markdown += "|----------|-----------|------------|---------|\n"

      matrix.each do |row|
        api_specs = row[:api_specs] ? '✅' : '❌'
        model_info = row[:model_info] ? '✅' : '❌'
        pricing = row[:pricing] ? '✅' : '❌'

        markdown += "| #{row[:provider]} | #{api_specs} | #{model_info} | #{pricing} |\n"
      end

      markdown
    end

    def self.update_feature_matrix_file
      markdown_content = generate_markdown

      File.write('FEATURE_MATRIX.md', markdown_content)
      puts "Updated FEATURE_MATRIX.md"
    end
  end
end

# Run the updater if this file is executed directly
if __FILE__ == $0
  Providers::FeatureMatrixUpdater.update_feature_matrix_file
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.