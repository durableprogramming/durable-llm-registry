# -*- encoding: utf-8 -*-
# stub: openapi_parser 2.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "openapi_parser".freeze
  s.version = "2.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["ota42y".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "parser for OpenAPI 3.0 or later".freeze
  s.email = ["ota42y@gmail.com".freeze]
  s.homepage = "https://github.com/ota42y/openapi_parser".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7.0".freeze)
  s.rubygems_version = "3.4.19".freeze
  s.summary = "OpenAPI3 parser".freeze

  s.installed_by_version = "3.4.19" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, [">= 1.16"])
  s.add_development_dependency(%q<fincop>.freeze, [">= 0"])
  s.add_development_dependency(%q<rake>.freeze, [">= 12.3.3"])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.0"])
  s.add_development_dependency(%q<rspec-parameterized>.freeze, [">= 0"])
  s.add_development_dependency(%q<simplecov>.freeze, [">= 0"])
  s.add_development_dependency(%q<steep>.freeze, [">= 0"])
  s.add_development_dependency(%q<base64>.freeze, ["~> 0.3.0"])
end
