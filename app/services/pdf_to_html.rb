class PdfToHtml
  def initialize(pdf)
    @pdf = pdf
  end

  def call
    @pdf.images.destroy_all
    @pdf.fonts.destroy_all

    @pdf.pdf.open do |tempfile|
      convert_to_html(tempfile)
    end
  end

  private

  def convert_to_html(tempfile)
    Dir.mktmpdir do |tmpdir|
      output_path = File.join(tmpdir, 'output')
      # Use -c flag for complex output with better font handling
      # Use -fontfullname to preserve full font names
      # Use -zoom to increase image resolution (default is 1.5)
      system('pdftohtml', '-c', '-s', '-fontfullname', '-zoom', '3.0', tempfile.path, output_path)

      html_file = "#{output_path}-html.html"
      return unless File.exist?(html_file)

      html_content = File.read(html_file)
      doc = Nokogiri::HTML.fragment(html_content)

      extract_and_attach_fonts(tempfile, doc)
      attach_images(tmpdir, doc)
      fix_font_family_quotes(doc)

      @pdf.update!(html_content: doc.to_html)
    end
  end

  def extract_and_attach_fonts(tempfile, doc)
    Dir.mktmpdir do |font_dir|
      # Build font mapping using mutool and pdffonts
      font_mapping = build_font_mapping(tempfile.path)

      # Extract fonts using mutool
      Dir.chdir(font_dir) do
        system('mutool', 'extract', tempfile.path)

        # Fix fonts missing cmap tables using FontForge
        fix_extracted_fonts(font_dir)

        # Attach fonts using the mapping
        font_mapping.each do |font_name, info|
          font_pattern = File.join(font_dir, "#{info[:expected_filename]}.{ttf,cff,otf,cid}")
          font_files = Dir.glob(font_pattern)

          if font_files.any?
            attach_font(font_files.first, font_name, info[:base_font_name])
          end
        end
      end
    end
  end

  def build_font_mapping(pdf_path)
    # Use pdffonts to get the list of fonts with their object IDs
    pdffonts_output = `pdffonts "#{pdf_path}" 2>&1`
    lines = pdffonts_output.split("\n")

    # Skip header lines (first 2 lines)
    font_lines = lines[2..-1] || []

    font_mapping = {}

    font_lines.each do |line|
      # Parse the line to extract font name and object ID
      # Format: name  type  encoding  emb sub uni object ID
      parts = line.split(/\s+/)
      next if parts.empty?

      font_name = parts[0]
      object_id = parts[-2].to_i # Second to last is the object number

      next if object_id == 0

      # Get the FontDescriptor object ID from mutool show
      mutool_output = `mutool show "#{pdf_path}" #{object_id} 2>&1`

      # Try to find FontDescriptor directly (Type1 fonts)
      font_descriptor_id = nil
      if mutool_output =~ /\/FontDescriptor\s+(\d+)\s+0\s+R/
        font_descriptor_id = $1.to_i
      # For Type0 fonts, we need to follow DescendantFonts
      # Match both array format [ 445 0 R ] and direct reference format 445 0 R
      elsif mutool_output =~ /\/DescendantFonts\s+(?:\[\s*)?(\d+)\s+0\s+R/
        descendant_id = $1.to_i
        descendant_output = `mutool show "#{pdf_path}" #{descendant_id} 2>&1`

        # If descendant is an array, get the first element
        if descendant_output =~ /^\[\s*(\d+)\s+0\s+R/
          actual_descendant_id = $1.to_i
          descendant_output = `mutool show "#{pdf_path}" #{actual_descendant_id} 2>&1`
        end

        if descendant_output =~ /\/FontDescriptor\s+(\d+)\s+0\s+R/
          font_descriptor_id = $1.to_i
        end
      end

      if font_descriptor_id
        # Extract base font name from mutool output (for metadata)
        base_font_name = nil
        if mutool_output =~ /\/BaseFont\s+\/([^\s]+)/
          base_font_name = $1.gsub(/#([0-9A-F]{2})/) { $1.hex.chr }
        end

        font_mapping[font_name] = {
          object_id: object_id,
          font_descriptor_id: font_descriptor_id,
          expected_filename: "font-#{font_descriptor_id.to_s.rjust(4, '0')}",
          base_font_name: base_font_name
        }
      end
    end

    font_mapping
  end

  def attach_font(font_path, font_name, base_font_name = nil)
    filename = File.basename(font_path)

    # Extract base font name if not provided
    unless base_font_name
      fc_output = `fc-scan #{font_path} 2>&1`
      base_font_name = fc_output.match(/fullname: "([^"]+)"/)[1] rescue nil
    end

    # Convert fonts to OTF for consistency and browser compatibility
    # Browsers cannot load standalone CFF files - they need to be wrapped in OpenType
    if filename.end_with?('.cff')
      converted_path = convert_to_otf(font_path, font_name)
      if converted_path
        font_path = converted_path
        filename = File.basename(converted_path)
      end
    end

    @pdf.fonts.attach(
      io: File.open(font_path),
      filename: filename,
      content_type: Marcel::MimeType.for(Pathname.new(font_path)),
      metadata: {
        font_name: font_name,
        base_font_name: base_font_name
      }
    )
  end

  def fix_extracted_fonts(font_dir)
    # Fix fonts that are missing cmap tables after extraction
    # This is necessary because mutool extract strips the cmap table
    Dir.glob(File.join(font_dir, '*.{ttf,otf}')).each do |font_path|
      rebuild_font_cmap(font_path)
    end
  end

  def rebuild_font_cmap(font_path)
    # Use FontForge to rebuild the cmap table for fonts extracted from PDFs
    # Maps glyphs by their index (GID) to match pdftohtml's character code output
    fontforge_script = <<~PYTHON
      import fontforge
      import sys

      try:
          font = fontforge.open("#{font_path}")

          # Check if font already has a valid cmap
          has_valid_cmap = False
          try:
              # Try to access the encoding - if it has mappings, cmap is valid
              mapped_glyphs = [g for g in font.glyphs() if g.unicode > 0]
              if font.encoding and len(mapped_glyphs) > 10:
                  has_valid_cmap = True
          except:
              pass

          if not has_valid_cmap:
              # Set encoding to UnicodeFull
              font.encoding = "UnicodeFull"

              # Map glyphs by their position/GID to match pdftohtml behavior
              # pdftohtml uses glyph indices as character codes in the HTML output
              # For symbol fonts without proper encoding, this preserves the mapping
              glyph_list = list(font.glyphs())

              for gid, glyph in enumerate(glyph_list):
                  # Map glyph at position gid to Unicode codepoint gid
                  # This way if pdftohtml outputs char code 0xD0 (208), it will use glyph at index 208
                  if glyph.glyphname != ".notdef" and gid < 0x10000:
                      glyph.unicode = gid

          # Generate the font (this will create proper cmap table)
          font.generate("#{font_path}")
          font.close()
      except Exception as e:
          sys.stderr.write(str(e))
          sys.exit(1)
    PYTHON

    # Run fontforge with Python script
    system('fontforge', '-lang=py', '-c', fontforge_script, out: File::NULL, err: File::NULL)
  end

  def convert_to_otf(font_path, font_name)
    # Use fontforge to convert CFF fonts to OTF
    # This ensures consistent format and can fix encoding issues
    # FontForge will automatically add missing tables like cmap
    otf_path = font_path.sub(/\.(cff|ttf|otf)$/, '.otf')

    # FontForge script that opens font and generates OTF
    # The Generate command will add necessary tables including cmap
    fontforge_script = <<~SCRIPT
      Open('#{font_path}')
      Generate('#{otf_path}')
    SCRIPT

    # Try using fontforge command line
    result = system('fontforge', '-lang=ff', '-c', fontforge_script, out: File::NULL, err: File::NULL)

    return otf_path if result && File.exist?(otf_path)

    # If fontforge not available or conversion fails, return nil to use original
    nil
  end

  def attach_images(tmpdir, doc)
    # Find all image files generated by pdftohtml
    image_files = Dir.glob(File.join(tmpdir, 'output*.{png,jpg,jpeg}'))

    # Attach images to Active Storage and rewrite URLs in HTML
    image_files.each do |image_path|
      filename = File.basename(image_path)

      # Attach the image
      blob = @pdf.images.attach(
        io: File.open(image_path),
        filename: filename,
        content_type: Marcel::MimeType.for(Pathname.new(image_path))
      ).last

      # Replace the local filename with the Active Storage URL using Nokogiri
      if blob
        storage_url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)

        # Update all img tags with matching src attribute
        doc.css("img[src*='#{filename}']").each do |img|
          img['src'] = storage_url
        end
      end
    end
  end

  def fix_font_family_quotes(doc)
    # Fix font-family values in CSS to add quotes around names with special characters
    # Find all style tags and inline styles
    doc.css('style').each do |style_tag|
      content = style_tag.content
      # Add quotes around font-family values that contain + or other special chars
      content = content.gsub(/font-family:\s*([^;'"]+)/) do |match|
        font_name = $1.strip
        # If the font name contains special characters and isn't already quoted, quote it
        if font_name.match?(/[+]/) && !font_name.match?(/^['"]/)
          "font-family: '#{font_name}'"
        else
          match
        end
      end
      style_tag.content = content
    end

    # Fix inline style attributes
    doc.css('[style]').each do |element|
      style = element['style']
      style = style.gsub(/font-family:\s*([^;'"]+)/) do |match|
        font_name = $1.strip
        if font_name.match?(/[+]/) && !font_name.match?(/^['"]/)
          "font-family: '#{font_name}'"
        else
          match
        end
      end
      element['style'] = style
    end
  end
end
