class PdfToHtml
  def initialize(pdf)
    @pdf = pdf
  end

  def call
    # Only remove images and fonts from previous pdftohtml conversions
    @pdf.images.select { |img| img.metadata['source'] == 'pdftohtml' }.each(&:purge)
    @pdf.fonts.each(&:purge)

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
      deduplicate_css_classes(doc)

      @pdf.update!(html_content: doc.to_html)
    end
  end

  def extract_and_attach_fonts(tempfile, doc)
    Dir.mktmpdir do |font_dir|
      # Build font mapping using mutool and pdffonts
      font_mapping = build_font_mapping(tempfile.path)

      # Detect italic fonts for CSS styling
      @italic_fonts = detect_italic_fonts(font_mapping)

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
            is_italic = @italic_fonts.include?(font_name)
            attach_font(font_files.first, font_name, info[:base_font_name], is_italic)
          end
        end
      end

      # Add italic styling to CSS
      add_italic_styling_to_css(doc)
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

  def attach_font(font_path, font_name, base_font_name = nil, is_italic = false)
    filename = File.basename(font_path)

    # Extract base font name if not provided
    unless base_font_name
      fc_output = `fc-scan #{font_path} 2>&1`
      base_font_name = fc_output.match(/fullname: "([^"]+)"/)[1] rescue nil
    end

    # Convert fonts to OTF for consistency and browser compatibility
    # Browsers cannot load standalone CFF files - they need to be wrapped in OpenType
    if filename.end_with?('.cff')
      converted_path = convert_to_otf(font_path, font_name, is_italic)
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
        source: 'pdftohtml',
        font_name: font_name,
        base_font_name: base_font_name,
        is_italic: is_italic
      }
    )
  end

  def fix_extracted_fonts(font_dir)
    # Fix fonts that are missing cmap tables after extraction
    # This is necessary because mutool extract strips the cmap table
    Dir.glob(File.join(font_dir, '*.{ttf,otf}')).each do |font_path|
      # Extract font name from path to check if it's italic
      font_id = File.basename(font_path, '.*').match(/font-(\d+)/)[1] rescue nil
      is_italic = false

      if font_id
        # Check if this font ID corresponds to an italic font
        font_descriptor_id = font_id.to_i
        @italic_fonts.each_value do |info|
          if info[:font_descriptor_id] == font_descriptor_id
            is_italic = true
            break
          end
        end
      end

      rebuild_font_cmap(font_path, is_italic)
    end
  end

  def rebuild_font_cmap(font_path, is_italic = false)
    # Use FontForge to rebuild the cmap table for fonts extracted from PDFs
    # Maps glyphs by their index (GID) to match pdftohtml's character code output

    # NOTE: We DON'T set italic angle here because:
    # 1. The glyphs are already drawn italic (baked into the glyph shapes)
    # 2. Setting italic angle would cause "double italic" rendering issues
    # 3. Browser positioning would be off since pdftohtml calculated positions for non-slanted fonts
    # Instead, we just mark the font as italic in metadata and let CSS handle it

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

  def convert_to_otf(font_path, font_name, is_italic = false)
    # Use fontforge to convert CFF fonts to OTF
    # This ensures consistent format and can fix encoding issues
    # FontForge will automatically add missing tables like cmap
    otf_path = font_path.sub(/\.(cff|ttf|otf)$/, '.otf')

    # NOTE: We DON'T set italic angle here for the same reason as rebuild_font_cmap
    # The glyphs are already italic, so setting angle would cause rendering issues

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
      file_size = File.size(image_path)

      # Check for duplicate: same source, filename, and file size
      existing = @pdf.images.find do |img|
        img.metadata['source'] == 'pdftohtml' &&
          img.filename.to_s == filename &&
          img.byte_size == file_size
      end

      blob = if existing
        existing
      else
        # Attach the image with metadata
        @pdf.images.attach(
          io: File.open(image_path),
          filename: filename,
          content_type: Marcel::MimeType.for(Pathname.new(image_path)),
          metadata: {
            source: 'pdftohtml'
          }
        ).last
      end

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

  def deduplicate_css_classes(doc)
    # pdftohtml generates one style block per page, but reuses the same class names
    # (like .ft310, .ft311) with different properties, causing later definitions
    # to override earlier ones. This method namespaces each style block's classes
    # to prevent conflicts.

    # Process each style tag with an index to create unique namespaces
    doc.css('style').each_with_index do |style_tag, block_index|
      content = style_tag.content

      # Skip empty style blocks
      next if content.strip.empty?

      # Find all class names defined in this style block
      class_names = content.scan(/\.(ft\d+)/).flatten.uniq

      next if class_names.empty?

      # Create mapping of old class names to new namespaced versions
      # Use style block index as namespace (e.g., .ft311 becomes .ft311-s3)
      class_mapping = {}
      class_names.each do |class_name|
        class_mapping[class_name] = "#{class_name}-s#{block_index}"
      end

      # Update class definitions in CSS
      class_mapping.each do |old_name, new_name|
        content = content.gsub(/\.#{Regexp.escape(old_name)}(\s*\{)/, ".#{new_name}\\1")
      end

      style_tag.content = content

      # Update HTML elements that use these classes
      # Find the page/div that corresponds to this style block
      # pdftohtml wraps each page in a div, and style blocks appear in order
      update_element_classes(doc, class_mapping, block_index)
    end
  end

  def update_element_classes(doc, class_mapping, block_index)
    # pdftohtml generates output where each page's content comes after its style block
    # We need to find elements that belong to this page/style block

    # Get all style tags
    style_tags = doc.css('style')
    current_style = style_tags[block_index]

    return unless current_style

    # Find the next sibling elements until we hit the next style tag
    elements_to_update = []
    current = current_style.next_sibling

    while current
      # Stop if we hit another style tag
      break if current.name == 'style'

      # Collect this element and its descendants
      if current.element?
        elements_to_update << current
        elements_to_update.concat(current.css('[class]'))
      end

      current = current.next_sibling
    end

    # Update class attributes
    elements_to_update.each do |element|
      next unless element['class']

      classes = element['class'].split(/\s+/)
      updated = false

      new_classes = classes.map do |cls|
        if class_mapping.key?(cls)
          updated = true
          class_mapping[cls]
        else
          cls
        end
      end

      element['class'] = new_classes.join(' ') if updated
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

  def detect_italic_fonts(font_mapping)
    # Detect which fonts are likely italic based on naming patterns and font families
    # Returns a hash of font_name => font_info for italic fonts
    italic_fonts = {}

    # Group fonts by their base name (without prefixes like FFLMLK, FFLMLO)
    font_families = {}
    font_mapping.each do |font_name, info|
      base_name = info[:base_font_name] || font_name

      # Extract the base family name by removing common prefixes
      # Example: "FFLMLK+MSTT31c52b" and "FFLMLO+MSTT31c55b" both become "MSTT31c52b" family
      family_key = base_name.gsub(/^[A-Z]+\+/, '')

      font_families[family_key] ||= []
      font_families[family_key] << { name: font_name, info: info }
    end

    # Detect italic fonts using various heuristics
    font_mapping.each do |font_name, info|
      base_name = info[:base_font_name] || font_name
      is_italic = false

      # Check for explicit italic/oblique indicators in font name
      if base_name.match?(/italic|oblique|ital|obli/i)
        is_italic = true
      end

      # Check for common italic font naming patterns
      # Many PDFs use prefixes like "FFLMLO" for italic vs "FFLMLK" for regular
      # The "LO" vs "LK" pattern is common in embedded fonts
      if base_name.match?(/\b[A-Z]+LO\+/i)
        is_italic = true
      end

      # Check for italic markers in the prefix (I, It, Ita)
      if base_name.match?(/^[A-Z]*I[A-Z]*\+/)
        is_italic = true
      end

      italic_fonts[font_name] = info if is_italic
    end

    italic_fonts
  end

  def add_italic_styling_to_css(doc)
    # Add font-style: italic to CSS rules for fonts we detected as italic
    # NOTE: This causes "double italic" rendering since the glyphs are already drawn italic,
    # which may result in slight positioning offsets. However, we accept this tradeoff
    # to ensure italic text is visually distinguishable. See PDF.md for details.
    return if @italic_fonts.empty?

    italic_font_names = @italic_fonts.keys

    doc.css('style').each do |style_tag|
      content = style_tag.content

      # Find all CSS rules and add font-style: italic for italic fonts
      content = content.gsub(/(\.[a-z0-9\-]+)\s*\{([^}]*font-family:\s*['"]?([^;'"]+)['"]?[^}]*)\}/i) do |match|
        selector = $1
        rule_content = $2
        font_family = $3.strip

        # Check if this font family matches any of our italic fonts
        if italic_font_names.any? { |name| font_family.include?(name) }
          # Add font-style: italic if not already present
          unless rule_content.match?(/font-style:\s*italic/)
            # Insert after font-family declaration
            rule_content = rule_content.sub(/(font-family:[^;]+;)/, "\\1font-style:italic;")
          end
        end

        "#{selector}{#{rule_content}}"
      end

      style_tag.content = content
    end
  end
end
