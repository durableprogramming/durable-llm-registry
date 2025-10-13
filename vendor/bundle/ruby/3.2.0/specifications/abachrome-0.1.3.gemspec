# -*- encoding: utf-8 -*-
# stub: abachrome 0.1.3 ruby lib

Gem::Specification.new do |s|
  s.name = "abachrome".freeze
  s.version = "0.1.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/durableprogramming/abachrome/blob/main/CHANGELOG.md", "homepage_uri" => "https://github.com/durableprogramming/abachrome", "source_code_uri" => "https://github.com/durableprogramming/abachrome" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Durable Programming".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-01"
  s.description = "Abachrome provides a robust set of tools for working with various color formats including hex, RGB, HSL, and named colors. Features support for multiple color spaces (RGB, HSL, Lab, Oklab), color space conversion, gamut mapping, CSS color parsing and formatting, and high-precision color calculations using BigDecimal.".freeze
  s.email = ["commercial@durableprogramming.com".freeze]
  s.homepage = "https://github.com/durableprogramming/abachrome".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.4.19".freeze
  s.summary = "A Ruby gem for parsing, manipulating, and managing colors".freeze

  s.installed_by_version = "3.4.19" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<dry-inflector>.freeze, ["~> 1.0"])
end
