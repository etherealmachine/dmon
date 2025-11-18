class GameHtml
  def initialize(pdf, base_dir)
    @pdf = pdf
    @base_dir = base_dir
  end

  def call
    return nil unless @pdf.html_content.present?

    # Create directory structure
    html_dir = File.join(@base_dir, 'html')
    fonts_dir = File.join(html_dir, 'fonts')
    images_dir = File.join(html_dir, 'images')

    FileUtils.mkdir_p(fonts_dir)
    FileUtils.mkdir_p(images_dir)

    # Build mappings of blob URLs to local filenames
    font_url_map = build_font_url_map(fonts_dir)
    image_url_map = build_image_url_map(images_dir)

    # Parse HTML content
    doc = Nokogiri::HTML.fragment(@pdf.html_content)

    # Rewrite font URLs in CSS
    rewrite_font_urls(doc, font_url_map)

    # Rewrite image URLs in HTML
    rewrite_image_urls(doc, image_url_map)

    # Add image constraints and improvements
    improve_html_for_export(doc)

    # Write index.html with proper HTML structure
    index_path = File.join(html_dir, 'index.html')
    File.write(index_path, build_complete_html(doc))

    html_dir
  end

  private

  def build_font_url_map(fonts_dir)
    url_map = {}

    return url_map unless @pdf.fonts.attached?

    @pdf.fonts.each do |font|
      # Get the blob URL
      blob_url = Rails.application.routes.url_helpers.rails_blob_path(font, only_path: true)

      # Copy the font file
      font_filename = font.filename.to_s
      font_path = File.join(fonts_dir, font_filename)

      font.open do |tempfile|
        FileUtils.cp(tempfile.path, font_path)
      end

      # Map the URL to the local path
      url_map[blob_url] = "./fonts/#{font_filename}"
    end

    url_map
  end

  def build_image_url_map(images_dir)
    url_map = {}

    return url_map unless @pdf.images.attached?

    # Only process pdftohtml images
    @pdf.images.select { |img| img.metadata['source'] == 'pdftohtml' }.each do |image|
      # Get the blob URL
      blob_url = Rails.application.routes.url_helpers.rails_blob_path(image, only_path: true)

      # Copy the image file
      image_filename = image.filename.to_s
      image_path = File.join(images_dir, image_filename)

      image.open do |tempfile|
        FileUtils.cp(tempfile.path, image_path)
      end

      # Map the URL to the local path
      url_map[blob_url] = "./images/#{image_filename}"
    end

    url_map
  end

  def rewrite_font_urls(doc, font_url_map)
    return if font_url_map.empty?

    # Find all @font-face rules in style tags
    doc.css('style').each do |style_tag|
      content = style_tag.content

      # Replace each font URL with its local path
      font_url_map.each do |blob_url, local_path|
        content.gsub!(blob_url, local_path)
      end

      style_tag.content = content
    end
  end

  def rewrite_image_urls(doc, image_url_map)
    return if image_url_map.empty?

    # Find all img tags and replace URLs
    doc.css('img').each do |img|
      src = img['src']
      next unless src

      if image_url_map.key?(src)
        img['src'] = image_url_map[src]
      end
    end
  end

  def improve_html_for_export(doc)
    # Add max-width constraints to images to prevent overflow
    doc.css('img').each do |img|
      existing_style = img['style'] || ''
      # Add max-width if not already present
      unless existing_style.include?('max-width')
        img['style'] = "#{existing_style}; max-width: 100%; height: auto;".strip
      end
    end

    # Add a wrapper div with constraints if not present
    unless doc.css('body, .page').any?
      doc.wrap('<div class="pdf-content"></div>')
    end
  end

  def build_complete_html(doc)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{@pdf.name || 'PDF Export'}</title>
        <style>
          body {
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
          }
          .pdf-content {
            max-width: 100%;
            background-color: white;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
            padding: 20px;
            margin: 0 auto;
          }
          img {
            max-width: 100%;
            height: auto;
            display: block;
          }
        </style>
      </head>
      <body>
        #{doc.to_html}
      </body>
      </html>
    HTML
  end
end
