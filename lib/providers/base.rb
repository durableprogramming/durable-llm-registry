require 'net/http'
require 'uri'
require 'fileutils'
require 'tempfile'
require_relative '../openapi/validator'
require_relative '../colored_logger'

module Providers
  class Base
    def initialize(logger: ColoredLogger.new(STDOUT))
      @logger = logger
    end

    def run
      raise NotImplementedError, "Subclasses must implement the run method"
    end

    private

    MAX_REDIRECTS = 10

    def download_openapi_spec(url)
      uri = URI(url)
      MAX_REDIRECTS.times do
        response = Net::HTTP.get_response(uri)
        case response
        when Net::HTTPRedirection
          location = response['location']
          break response.body if location.nil? || location.empty?
          uri = URI.join(uri.to_s, location)
        else
          return response.body
        end
      end
      raise "Too many redirects for #{url}"
    end

    def validate_spec(spec_content)
      temp_file = Tempfile.new(['openapi', '.yaml'])
      temp_file.write(spec_content)
      temp_file.close
      valid, errors = OpenAPI::Validator.validate(temp_file.path)
      temp_file.unlink
      [valid, errors]
    end

    def save_spec_to_catalog(provider_name, spec_content)
      catalog_dir = "catalog/#{provider_name}"
      FileUtils.mkdir_p(catalog_dir)
      File.write("#{catalog_dir}/openapi.yaml", spec_content)
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.