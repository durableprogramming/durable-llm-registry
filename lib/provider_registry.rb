require 'dry/inflector'

module Providers
  class Registry
    def initialize(inflector: Dry::Inflector.new)
      @inflector = inflector
      @providers = {}
      load_providers
    end

    def all
      @providers.values
    end

    def find_by_name(name)
      @providers[name]
    end

    def names
      @providers.keys
    end

    private

    def load_providers
      files = Dir.glob('lib/providers/*.rb')
      files.each do |file|
        next if File.basename(file) == 'base.rb'

        require_relative file.sub('lib/', '')

        filename = File.basename(file, '.rb')
        class_name = @inflector.classify(filename)
        class_name = adjust_class_name(class_name)

        provider_class = Providers.const_get(class_name)
        @providers[filename] = provider_class
      end
    end

    def adjust_class_name(class_name)
      class_name.gsub('Openrouter', 'OpenRouter').gsub('Xai', 'XAI').gsub('Firework', 'Fireworks')
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.