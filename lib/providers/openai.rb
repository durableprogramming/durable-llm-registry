require 'json'
require_relative 'base'

module Providers
  class Openai < Base
    def can_pull_api_specs?
      true
    end

    def can_pull_model_info?
      false
    end

    def can_pull_pricing?
      false
    end

    def openapi_url
      'https://raw.githubusercontent.com/api-evangelist/openai/main/openapi/chat-openapi-original.yml'
    end

    def run
      # Download and save the OpenAPI spec
      @logger.info("Downloading OpenAI OpenAPI spec...")
      spec_content = download_openapi_spec(openapi_url)
      if spec_content
        save_spec_to_catalog('openai', spec_content)
        @logger.info("Updated OpenAI OpenAPI spec")
      else
        @logger.error("Failed to download OpenAPI spec from #{openapi_url}")
        return
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.