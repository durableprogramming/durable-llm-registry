require_relative 'provider_registry'
require_relative 'feature_matrix_updater'

module Providers
  class Updater
    def initialize(inflector: Dry::Inflector.new)
      @inflector = inflector
    end

    def run
      registry = Registry.new(inflector: @inflector)

      registry.all.each do |provider_class|
        provider_instance = provider_class.new
        provider_instance.run
      end

      # Update the feature matrix after all providers have been updated
      Providers::FeatureMatrixUpdater.update_feature_matrix_file

      # Update the catalogs after all providers have been updated
      require_relative 'catalog_updater'
      CatalogUpdater.update_catalogs
    end
  end
end

if __FILE__ == $0
  Providers::Updater.new.run
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.