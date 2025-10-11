require 'minitest/autorun'
require 'mocha/minitest'
require 'tempfile'
require 'yaml'
require 'json'
require_relative '../lib/openapi/validator'

class TestValidator < Minitest::Test
  def setup
    # Setup if needed
  end

  # Tests for validate method

  def test_validate_with_valid_openapi_spec
    valid_spec = {
      'openapi' => '3.0.0',
      'info' => {
        'title' => 'Test API',
        'version' => '1.0.0'
      },
      'paths' => {
        '/test' => {
          'get' => {
            'responses' => {
              '200' => {
                'description' => 'OK'
              }
            }
          }
        }
      }
    }

    Tempfile.create(['valid_spec', '.yaml']) do |file|
      file.write(valid_spec.to_yaml)
      file.flush

      success, errors = OpenAPI::Validator.validate(file.path)
      assert success, "Expected validation to succeed"
      assert_nil errors, "Expected no errors"
    end
  end

  def test_validate_with_invalid_yaml_syntax
    Tempfile.create(['invalid_yaml', '.yaml']) do |file|
      file.write("openapi: 3.0.0\n  invalid: yaml: syntax:")
      file.flush

      success, errors = OpenAPI::Validator.validate(file.path)
      refute success, "Expected validation to fail"
      assert_match %r{YAML syntax error}, errors
    end
  end

  def test_validate_with_openapi_parsing_error
    # Mock OpenAPIParser to raise an error
    invalid_spec = {
      'openapi' => '3.0.0',
      'info' => { 'title' => 'Test', 'version' => '1.0' },
      'paths' => {}
    }

    Tempfile.create(['parsing_error', '.yaml']) do |file|
      file.write(invalid_spec.to_yaml)
      file.flush

      OpenAPIParser.stub :parse, ->(_) { raise OpenAPIParser::OpenAPIError.new('Parsing failed') } do
        success, errors = OpenAPI::Validator.validate(file.path)
        refute success, "Expected validation to fail"
        assert_match %r{OpenAPI parsing error}, errors
      end
    end
  end

  def test_validate_with_validation_errors
    spec_with_errors = {
      'openapi' => '3.0.0',
      'info' => {
        'title' => 'Test API',
        'version' => '1.0.0'
      },
      'paths' => {
        '/test' => {
          'get' => {
            # Missing responses
          }
        }
      }
    }

    Tempfile.create(['validation_errors', '.yaml']) do |file|
      file.write(spec_with_errors.to_yaml)
      file.flush

      success, errors = OpenAPI::Validator.validate(file.path)
      refute success, "Expected validation to fail"
      assert_match %r{Operation GET \/test missing 'responses'}, errors
    end
  end

  def test_validate_with_generic_error
    Tempfile.create(['generic_error', '.yaml']) do |file|
      file.write("openapi: 3.0.0\ninfo:\n  title: Test\n  version: 1.0")
      file.flush

      # Mock File.read to raise an error
      File.stub :read, ->(_) { raise StandardError.new('File read error') } do
        success, errors = OpenAPI::Validator.validate(file.path)
        refute success, "Expected validation to fail"
        assert_match %r{Validation error: File read error}, errors
      end
    end
  end

  # Tests for validate_openapi_version

  def test_validate_openapi_version_valid
    spec = { 'openapi' => '3.1.0' }
    errors = OpenAPI::Validator.send(:validate_openapi_version, spec)
    assert_empty errors
  end

  def test_validate_openapi_version_invalid_format
    spec = { 'openapi' => '2.0.0' }
    errors = OpenAPI::Validator.send(:validate_openapi_version, spec)
    assert_equal 1, errors.size
    assert_match %r{Invalid or missing OpenAPI version}, errors.first
  end

  def test_validate_openapi_version_missing
    spec = {}
    errors = OpenAPI::Validator.send(:validate_openapi_version, spec)
    assert_equal 1, errors.size
    assert_match %r{Invalid or missing OpenAPI version}, errors.first
  end

  def test_validate_openapi_version_wrong_format
    spec = { 'openapi' => '3.0' }
    errors = OpenAPI::Validator.send(:validate_openapi_version, spec)
    assert_equal 1, errors.size
    assert_match %r{Invalid or missing OpenAPI version}, errors.first
  end

  # Tests for validate_info

  def test_validate_info_complete_valid
    spec = {
      'info' => {
        'title' => 'Test API',
        'version' => '1.0.0',
        'contact' => {
          'email' => 'test@example.com'
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_info, spec)
    assert_empty errors
  end

  def test_validate_info_missing_info
    spec = {}
    errors = OpenAPI::Validator.send(:validate_info, spec)
    assert_equal 1, errors.size
    assert_match %r{Missing 'info' section}, errors.first
  end

  def test_validate_info_missing_title
    spec = {
      'info' => {
        'version' => '1.0.0'
      }
    }
    errors = OpenAPI::Validator.send(:validate_info, spec)
    assert_equal 1, errors.size
    assert_match %r{Missing 'info.title'}, errors.first
  end

  def test_validate_info_missing_version
    spec = {
      'info' => {
        'title' => 'Test API'
      }
    }
    errors = OpenAPI::Validator.send(:validate_info, spec)
    assert_equal 1, errors.size
    assert_match %r{Missing 'info.version'}, errors.first
  end

  def test_validate_info_invalid_email
    spec = {
      'info' => {
        'title' => 'Test API',
        'version' => '1.0.0',
        'contact' => {
          'email' => 'invalid-email'
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_info, spec)
    assert_equal 1, errors.size
    assert_match %r{Invalid contact email format}, errors.first
  end

  def test_validate_info_valid_email
    spec = {
      'info' => {
        'title' => 'Test API',
        'version' => '1.0.0',
        'contact' => {
          'email' => 'valid.email@example.com'
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_info, spec)
    assert_empty errors
  end

  # Tests for validate_servers

  def test_validate_servers_valid
    spec = {
      'servers' => [
        { 'url' => 'https://api.example.com' },
        { 'url' => 'https://staging.example.com/v1' }
      ]
    }
    errors = OpenAPI::Validator.send(:validate_servers, spec)
    assert_empty errors
  end

  def test_validate_servers_missing_url
    spec = {
      'servers' => [
        {},
        { 'url' => 'https://api.example.com' }
      ]
    }
    errors = OpenAPI::Validator.send(:validate_servers, spec)
    assert_equal 1, errors.size
    assert_match %r{Server 0 missing 'url'}, errors.first
  end

  def test_validate_servers_invalid_url
    spec = {
      'servers' => [
        { 'url' => 'not-a-valid-url' }
      ]
    }
    errors = OpenAPI::Validator.send(:validate_servers, spec)
    assert_equal 1, errors.size
    assert_match %r{Server 0 has invalid URL format}, errors.first
  end

  def test_validate_servers_no_servers
    spec = {}
    errors = OpenAPI::Validator.send(:validate_servers, spec)
    assert_empty errors
  end

  # Tests for validate_paths

  def test_validate_paths_valid
    spec = {
      'paths' => {
        '/users' => {
          'get' => {
            'responses' => {
              '200' => { 'description' => 'Success' }
            }
          },
          'post' => {
            'responses' => {
              '201' => { 'description' => 'Created' }
            }
          }
        },
        '/users/{id}' => {
          'get' => {
            'parameters' => [
              { 'name' => 'id', 'in' => 'path', 'required' => true }
            ],
            'responses' => {
              '200' => { 'description' => 'Success' }
            }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_empty errors
  end

  def test_validate_paths_missing_paths
    spec = {}
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Missing or empty 'paths' section}, errors.first
  end

  def test_validate_paths_empty_paths
    spec = { 'paths' => {} }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Missing or empty 'paths' section}, errors.first
  end

  def test_validate_paths_invalid_path_format
    spec = {
      'paths' => {
        'users' => {  # Missing leading slash
          'get' => {
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Path 'users' must start with '\/'}, errors.first
  end

  def test_validate_paths_missing_responses
    spec = {
      'paths' => {
        '/users' => {
          'get' => {}
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Operation GET \/users missing 'responses'}, errors.first
  end

  def test_validate_paths_invalid_method
    spec = {
      'paths' => {
        '/users' => {
          'invalid' => {
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_empty errors  # Invalid methods are ignored, only valid HTTP methods are checked
  end

  def test_validate_paths_parameters_missing_name
    spec = {
      'paths' => {
        '/users' => {
          'get' => {
            'parameters' => [
              { 'in' => 'query' }  # Missing name
            ],
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Parameter 0 in GET \/users missing 'name'}, errors.first
  end

  def test_validate_paths_parameters_invalid_in
    spec = {
      'paths' => {
        '/users' => {
          'get' => {
            'parameters' => [
              { 'name' => 'test', 'in' => 'invalid' }
            ],
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Parameter test in GET \/users has invalid 'in' value}, errors.first
  end

  def test_validate_paths_parameters_path_not_required
    spec = {
      'paths' => {
        '/users/{id}' => {
          'get' => {
            'parameters' => [
              { 'name' => 'id', 'in' => 'path' }  # Missing required: true
            ],
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_paths, spec)
    assert_equal 1, errors.size
    assert_match %r{Path parameter id in GET \/users\/\{id\} must be required}, errors.first
  end

  # Tests for validate_components

  def test_validate_components_valid
    spec = {
      'components' => {
        'schemas' => {
          'User' => {
            'type' => 'object',
            'properties' => {
              'name' => { 'type' => 'string' },
              'age' => { 'type' => 'integer' }
            }
          }
        },
        'securitySchemes' => {
          'bearerAuth' => {
            'type' => 'http',
            'scheme' => 'bearer'
          },
          'apiKey' => {
            'type' => 'apiKey',
            'in' => 'header',
            'name' => 'X-API-Key'
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_components, spec)
    assert_empty errors
  end

  def test_validate_components_no_components
    spec = {}
    errors = OpenAPI::Validator.send(:validate_components, spec)
    assert_empty errors
  end

  def test_validate_components_invalid_schema_type
    spec = {
      'components' => {
        'schemas' => {
          'User' => {
            'type' => 'invalid_type'
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_components, spec)
    assert_equal 1, errors.size
    assert_match %r{Schema 'User' has invalid type 'invalid_type'}, errors.first
  end

  def test_validate_components_security_scheme_missing_type
    spec = {
      'components' => {
        'securitySchemes' => {
          'auth' => {
            'scheme' => 'bearer'
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_components, spec)
    assert_equal 1, errors.size
    assert_match %r{Security scheme 'auth' missing 'type'}, errors.first
  end

  def test_validate_components_api_key_missing_in
    spec = {
      'components' => {
        'securitySchemes' => {
          'apiKey' => {
            'type' => 'apiKey',
            'name' => 'key'
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_components, spec)
    assert_equal 1, errors.size
    assert_match %r{API key security scheme 'apiKey' missing 'in'}, errors.first
  end

  def test_validate_components_http_missing_scheme
    spec = {
      'components' => {
        'securitySchemes' => {
          'bearer' => {
            'type' => 'http'
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_components, spec)
    assert_equal 1, errors.size
    assert_match %r{HTTP security scheme 'bearer' missing 'scheme'}, errors.first
  end

  # Tests for validate_schema

  def test_validate_schema_object_with_properties
    schema = {
      'type' => 'object',
      'properties' => {
        'name' => { 'type' => 'string' },
        'details' => {
          'type' => 'object',
          'properties' => {
            'age' => { 'type' => 'integer' }
          }
        }
      }
    }
    errors = OpenAPI::Validator.send(:validate_schema, 'TestSchema', schema)
    assert_empty errors
  end

  def test_validate_schema_array_with_items
    schema = {
      'type' => 'array',
      'items' => { 'type' => 'string' }
    }
    errors = OpenAPI::Validator.send(:validate_schema, 'TestArray', schema)
    assert_empty errors
  end

  def test_validate_schema_array_missing_items
    schema = {
      'type' => 'array'
    }
    errors = OpenAPI::Validator.send(:validate_schema, 'TestArray', schema)
    assert_equal 1, errors.size
    assert_match %r{Array schema 'TestArray' missing 'items'}, errors.first
  end

  def test_validate_schema_primitive_types
    %w[string number integer boolean].each do |type|
      schema = { 'type' => type }
      errors = OpenAPI::Validator.send(:validate_schema, 'Test', schema)
      assert_empty errors, "Failed for type #{type}"
    end
  end

  def test_validate_schema_invalid_type
    schema = { 'type' => 'invalid' }
    errors = OpenAPI::Validator.send(:validate_schema, 'Test', schema)
    assert_equal 1, errors.size
    assert_match %r{Schema 'Test' has invalid type 'invalid'}, errors.first
  end

  def test_validate_schema_non_hash
    schema = "not a hash"
    errors = OpenAPI::Validator.send(:validate_schema, 'Test', schema)
    assert_empty errors
  end

  # Tests for validate_security

  def test_validate_security_valid
    spec = {
      'components' => {
        'securitySchemes' => {
          'bearerAuth' => { 'type' => 'http', 'scheme' => 'bearer' }
        }
      },
      'security' => [
        { 'bearerAuth' => [] }
      ]
    }
    errors = OpenAPI::Validator.send(:validate_security, spec)
    assert_empty errors
  end

  def test_validate_security_undefined_scheme
    spec = {
      'security' => [
        { 'undefinedScheme' => [] }
      ]
    }
    errors = OpenAPI::Validator.send(:validate_security, spec)
    assert_equal 1, errors.size
    assert_match %r{Security requirement 0 references undefined scheme 'undefinedScheme'}, errors.first
  end

  def test_validate_security_no_security
    spec = {}
    errors = OpenAPI::Validator.send(:validate_security, spec)
    assert_empty errors
  end

  # Tests for valid_email?

  def test_valid_email_valid_emails
    valid_emails = [
      'test@example.com',
      'user.name+tag@example.co.uk',
      'test.email@subdomain.example.com'
    ]
    valid_emails.each do |email|
      assert OpenAPI::Validator.send(:valid_email?, email), "Expected #{email} to be valid"
    end
  end

  def test_valid_email_invalid_emails
    invalid_emails = [
      'invalid',
      'invalid@',
      '@example.com',
      'test@.com',
      'test..test@example.com'
    ]
    invalid_emails.each do |email|
      refute OpenAPI::Validator.send(:valid_email?, email), "Expected #{email} to be invalid"
    end
  end

  # Tests for valid_url?

  def test_valid_url_valid_urls
    valid_urls = [
      'https://example.com',
      'http://api.example.com/v1',
      'https://subdomain.example.com/path?query=value'
    ]
    valid_urls.each do |url|
      assert OpenAPI::Validator.send(:valid_url?, url), "Expected #{url} to be valid"
    end
  end

  def test_valid_url_invalid_urls
    invalid_urls = [
      'not-a-url',
      'ftp://example.com',
      'https://',
      '://example.com'
    ]
    invalid_urls.each do |url|
      refute OpenAPI::Validator.send(:valid_url?, url), "Expected #{url} to be invalid"
    end
  end

  def test_valid_url_with_uri_error
    # Mock URI.parse to raise an exception
    URI.stub :parse, ->(_) { raise URI::InvalidURIError } do
      refute OpenAPI::Validator.send(:valid_url?, 'invalid://url')
    end
  end
end