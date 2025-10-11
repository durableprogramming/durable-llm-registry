require 'logger'

class ColoredLogger < Logger
  COLORS = {
    'DEBUG' => "\e[36m",  # Cyan
    'INFO' => "\e[34m",   # Blue
    'WARN' => "\e[33m",   # Yellow
    'ERROR' => "\e[31m",  # Red
    'FATAL' => "\e[35m",  # Magenta
    'UNKNOWN' => "\e[37m", # White
    'CACHE' => "\e[90m"   # Gray
  }.freeze

  RESET = "\e[0m".freeze

  def initialize(*args)
    super
    self.formatter = proc do |severity, datetime, progname, msg|
      tag = if msg =~ /cache/i
              'CACHE'
            else
              severity
            end
      color = COLORS[tag] || "\e[37m"
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{tag}] #{color}#{msg}#{RESET}\n"
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.