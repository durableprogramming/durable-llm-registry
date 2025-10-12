require_relative "erb/version"
require_relative "erb/error"
require_relative "erb/view"
require "erb"

module Stellar
  module Erb
    # :nodoc:
    # This module provides a lightweight ERB template rendering system
    # with error handling capabilities.

    class Error < StandardError; end

    # Shortcut method for rendering templates
    # This method provides a convenient interface to render ERB templates
    # directly from the Stellar::Erb module without instantiating a View.
    #
    # @param template_path [String] The path to the ERB template file
    # @param locals [Hash] A hash of local variables to be made available in the template
    # @return [String] The rendered template result
    # 
    # @example Render a template with variables
    #   Stellar::Erb.render("path/to/template.erb", name: "World")
    #
    # @example Render a template without variables
    #   Stellar::Erb.render("path/to/simple.erb")
    #
    # @raise [Stellar::Erb::Error] if an error occurs during template rendering
    # @raise [Errno::ENOENT] if the template file doesn't exist
    def self.render(template_path, locals = {})
      View.render(template_path, locals)
    end

    # Renders an ERB template from a string instead of a file
    # This is useful for template strings that are generated dynamically
    # or stored in a database rather than in files.
    #
    # @param str [String] The ERB template string to render
    # @param locals [Hash] A hash of local variables to be made available in the template
    # @return [String] The rendered template result
    #
    # @example Render a string template with variables
    #   Stellar::Erb.render_string("<p>Hello, <%= name %></p>", name: "World")
    #
    # @example Render a string template without variables
    #   Stellar::Erb.render_string("<p>Static content</p>")
    #
    # @raise [Stellar::Erb::Error] if an error occurs during template rendering
    def self.render_string(str, locals = {})
      v = View.new(nil, locals)
      v.template_content = str
      v.render()
    end
  end
end
