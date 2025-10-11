require 'yaml'
require 'json'
require 'openapi_parser'

module OpenAPI
  class Validator
    def self.validate(spec_path)
      errors = []

      begin
        # Load the spec
        spec_content = File.read(spec_path)
        spec = YAML.safe_load(spec_content)

        # Parse with openapi_parser
        OpenAPIParser.parse(spec)

        # Additional thorough validations
        errors.concat(validate_openapi_version(spec))
        errors.concat(validate_info(spec))
        errors.concat(validate_servers(spec))
        errors.concat(validate_paths(spec))
        errors.concat(validate_components(spec))
        errors.concat(validate_security(spec))

        if errors.empty?
          [true, nil]
        else
          [false, errors.join("\n")]
        end
      rescue Psych::SyntaxError => e
        [false, "YAML syntax error: #{e.message}"]
      rescue OpenAPIParser::OpenAPIError => e
        [false, "OpenAPI parsing error: #{e.message}"]
      rescue => e
        [false, "Validation error: #{e.message}"]
      end
    end

    private

    def self.validate_openapi_version(spec)
      errors = []
      version = spec['openapi']
      unless version && version.match?(/^3\.\d+\.\d+$/)
        errors << "Invalid or missing OpenAPI version. Must be 3.x.x"
      end
      errors
    end

    def self.validate_info(spec)
      errors = []
      info = spec['info']
      unless info
        errors << "Missing 'info' section"
        return errors
      end

      unless info['title']
        errors << "Missing 'info.title'"
      end

      unless info['version']
        errors << "Missing 'info.version'"
      end

      # Validate contact if present
      if info['contact']
        contact = info['contact']
        if contact['email'] && !valid_email?(contact['email'])
          errors << "Invalid contact email format"
        end
      end

      errors
    end

    def self.validate_servers(spec)
      errors = []
      servers = spec['servers']
      if servers
        servers.each_with_index do |server, index|
          unless server['url']
            errors << "Server #{index} missing 'url'"
          end
          # Validate URL format
          if server['url'] && !valid_url?(server['url'])
            errors << "Server #{index} has invalid URL format"
          end
        end
      end
      errors
    end

    def self.validate_paths(spec)
      errors = []
      paths = spec['paths']
      unless paths && !paths.empty?
        errors << "Missing or empty 'paths' section"
        return errors
      end

      paths.each do |path, operations|
        unless path.start_with?('/')
          errors << "Path '#{path}' must start with '/'"
        end

        operations.each do |method, operation|
          next unless %w[get post put delete patch options head].include?(method)

          unless operation['responses']
            errors << "Operation #{method.upcase} #{path} missing 'responses'"
          end

          # Validate parameters
          if operation['parameters']
            operation['parameters'].each_with_index do |param, idx|
              unless param['name']
                errors << "Parameter #{idx} in #{method.upcase} #{path} missing 'name'"
              end
              unless param['in'] && %w[query header path cookie].include?(param['in'])
                errors << "Parameter #{param['name'] || idx} in #{method.upcase} #{path} has invalid 'in' value"
              end
              if param['in'] == 'path' && !param['required']
                errors << "Path parameter #{param['name']} in #{method.upcase} #{path} must be required"
              end
            end
          end
        end
      end
      errors
    end

    def self.validate_components(spec)
      errors = []
      components = spec['components']
      return errors unless components

      # Validate schemas
      if components['schemas']
        components['schemas'].each do |name, schema|
          errors.concat(validate_schema(name, schema))
        end
      end

      # Validate security schemes
      if components['securitySchemes']
        components['securitySchemes'].each do |name, scheme|
          unless scheme['type']
            errors << "Security scheme '#{name}' missing 'type'"
          end
          if scheme['type'] == 'apiKey' && !scheme['in']
            errors << "API key security scheme '#{name}' missing 'in'"
          end
          if scheme['type'] == 'http' && !scheme['scheme']
            errors << "HTTP security scheme '#{name}' missing 'scheme'"
          end
        end
      end

      errors
    end

    def self.validate_schema(name, schema, path = [])
      errors = []
      return errors unless schema.is_a?(Hash)

      type = schema['type']
      if type && !%w[object array string number integer boolean].include?(type)
        errors << "Schema '#{name}' has invalid type '#{type}'"
      end

      # Validate properties for objects
      if type == 'object'
        properties = schema['properties']
        if properties
          properties.each do |prop_name, prop_schema|
            prop_path = path + [prop_name]
            errors.concat(validate_schema("#{name}.#{prop_name}", prop_schema, prop_path))
          end
        end
      end

      # Validate items for arrays
      if type == 'array'
        items = schema['items']
        unless items
          errors << "Array schema '#{name}' missing 'items'"
        else
          errors.concat(validate_schema("#{name}[]", items, path + ['[]']))
        end
      end

      errors
    end

    def self.validate_security(spec)
      errors = []
      security = spec['security']
      if security
        security.each_with_index do |req, index|
          req.each do |scheme, scopes|
            # Check if scheme exists in components
            unless spec.dig('components', 'securitySchemes', scheme)
              errors << "Security requirement #{index} references undefined scheme '#{scheme}'"
            end
          end
        end
      end
      errors
    end

    def self.valid_email?(email)
      email.match?(/\A[\w+\-]+(\.[\w+\-]+)*@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    end

    def self.valid_url?(url)
      uri = URI.parse(url)
      uri.scheme && uri.host && !uri.host.empty? && %w[http https].include?(uri.scheme)
    rescue
      false
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.