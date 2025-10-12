# frozen_string_literal: true

module Stellar
  module Erb
    class Error < StandardError
      attr_accessor :template_path, :original_error, :line_number

      def initialize(message = nil, template_path: nil, original_error: nil, line_number: nil)
        @template_path = template_path
        @original_error = original_error
        @line_number = line_number
        message ||= self.class.name
        super(message)
      end

      def to_s
        message = super
        if template_path && line_number
          "#{message} in '#{template_path}' on line #{line_number}"
        elsif template_path
          "#{message} in '#{template_path}'"
        else
          message
        end
      end

      def self.wrap(error, template_path: nil)
        return error if error.is_a?(self)

        line_number = extract_line_number(error, template_path)
        message = error.message

        new(message,
            template_path: template_path,
            original_error: error,
            line_number: line_number)
      end

      def self.extract_line_number(error, template_path)
        return nil unless template_path && error.backtrace

        backtrace_line = error.backtrace.find { |line| line.include?(template_path) }
        return nil unless backtrace_line

        match = backtrace_line.match(/:(\d+):/)
        match ? match[1].to_i : nil
      end

      def context_lines(number_of_lines = 5)
        return [] unless template_path && line_number && File.exist?(template_path)

        lines = File.readlines(template_path)
        start_line = [line_number - number_of_lines - 1, 0].max
        end_line = [line_number + number_of_lines - 1, lines.length - 1].min

        context = []
        (start_line..end_line).each do |i|
          prefix = i + 1 == line_number ? "=>" : "  "
          context << "#{prefix} #{i + 1}: #{lines[i].chomp}"
        end

        context
      end
    end
  end
end
