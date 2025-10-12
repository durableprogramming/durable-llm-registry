require 'nokogiri'
require 'abachrome'
require 'abachrome/parsers/css'

Dir.glob('static/logos/*.svg').each do |file|
  doc = Nokogiri::XML(File.read(file))

  # Find elements with color attributes
  doc.xpath('//*[@fill or @stroke or @color]').each do |elem|
    ['fill', 'stroke', 'color'].each do |attr|
      next unless elem[attr]
      color_str = elem[attr]
      next if color_str == 'none' || color_str.start_with?('url(')

      begin
        color = Abachrome::Parsers::CSS.parse(color_str)
        white = Abachrome::Parsers::CSS.parse('#ffffff')
        durable_blue = Abachrome::Parsers::CSS.parse('#111d44')
        blended = color.blend(white.blend(durable_blue, 0.4), 0.7)
        elem[attr] = blended.rgb_hex
      end
    end
  end

  provider = File.basename(file, '.svg')
  output_file = "catalog/#{provider}/logo.svg"
  File.write(output_file, doc.to_xml)
end
