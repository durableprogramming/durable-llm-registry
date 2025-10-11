# -*- encoding: utf-8 -*-
# stub: stellar-erb 0.1.1 ruby lib

Gem::Specification.new do |s|
  s.name = "stellar-erb".freeze
  s.version = "0.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/durableprogramming/stellar-erb/blob/main/CHANGELOG.md", "homepage_uri" => "https://github.com/durableprogramming/stellar-erb", "source_code_uri" => "https://github.com/durableprogramming/stellar-erb" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Durable Programming, LLC".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-01"
  s.description = "Stellar::Erb provides a method for reading .erb files from disk and rendering them to strings, passing arguments, and catching errors with correct backtraces and context.".freeze
  s.email = ["djberube@durableprogramming.com".freeze]
  s.homepage = "https://github.com/durableprogramming/stellar-erb".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.4.19".freeze
  s.summary = "A safe, easy to use wrapper for ERB views outside of Rails".freeze

  s.installed_by_version = "3.4.19" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<erb>.freeze, ["~> 4.0"])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0"])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.21"])
end
