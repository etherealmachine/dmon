class ClassifyImages
  def initialize(pdf, api_key: nil, reclassify: false)
    @api_key = api_key || ENV['OPENAI_API_KEY']
    @client = @api_key ? OpenAI::Client.new(access_token: @api_key) : nil
    @pdf = pdf
    @reclassify = reclassify
  end

  def call
    raise "OpenAI API key not configured" unless @client
    raise "No images to classify" if @pdf.images.blank?

    @pdf.images.each do |image|
      # Skip if already classified unless reclassify flag is set
      next if already_classified?(image) && !@reclassify

      classify_image(image)
    end
  end

  private

  def already_classified?(image)
    image.blob.metadata['classification'].present? &&
      image.blob.metadata['classified_at'].present?
  end

  def classify_image(image)
    # Convert image to base64 for OpenAI API
    image_data = image.download
    base64_image = Base64.strict_encode64(image_data)

    # Determine the image format
    content_type = image.content_type
    image_format = case content_type
                   when 'image/jpeg' then 'jpeg'
                   when 'image/png' then 'png'
                   when 'image/gif' then 'gif'
                   when 'image/webp' then 'webp'
                   else 'jpeg' # default fallback
                   end

    begin
      response = @client.chat(
        parameters: {
          model: "gpt-5-nano",
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: classification_prompt
                },
                {
                  type: "image_url",
                  image_url: {
                    url: "data:#{content_type};base64,#{base64_image}"
                  }
                }
              ]
            }
          ],
        }
      )

      content = response.dig("choices", 0, "message", "content") || ""

      # Parse the response to extract structured data
      parsed = parse_classification_response(content)

      # Update the image metadata
      image.blob.update(
        metadata: image.blob.metadata.merge(
          'classification': parsed[:classification],
          'description': parsed[:description],
          'should_delete': parsed[:should_delete],
          'classified_at': Time.current.iso8601
        )
      )

      Rails.logger.info "Classified image #{image.filename}: #{parsed[:classification]} (delete: #{parsed[:should_delete]})"
    rescue => e
      Rails.logger.error "Failed to classify image #{image.filename}: #{e.class} - #{e.message}"
      # Mark as failed but don't crash
      image.blob.update(
        metadata: image.blob.metadata.merge(
          'classification_error': e.message,
          'should_delete': false # Keep it if we can't classify
        )
      )
    end
  end

  def classification_prompt
    base_prompt = <<~PROMPT
      You are analyzing an image extracted from a tabletop RPG PDF.

      CONTEXT FROM THE PDF:
      #{@pdf.text_content}

      Use this context to better understand the purpose and content of the image.
      For example:
      - If the PDF is about a specific adventure, images may be maps or NPCs from that adventure
      - If the PDF mentions specific locations, images may depict those locations
      - If the PDF describes monsters or characters, images may be their illustrations
      - Use the text to identify what makes this image valuable or not for players

      Please classify this image and determine if it should be kept or deleted.

      IMPORTANT: Images must be STANDALONE and usable by themselves when displayed to players.

      Images to KEEP:
      - Maps, dungeon layouts, floor plans (with labels, keys, and details visible)
      - Character portraits, monster illustrations (fully rendered, not silhouettes)
      - Item illustrations, equipment diagrams (complete illustrations)
      - Scene illustrations that depict story moments (fully rendered scenes)
      - Handouts meant for players (complete and readable)
      - Tables, charts with game information (complete with all text)

      Images to DELETE:
      - Silhouettes or single-color cutouts (these are background layers)
      - Mostly white/blank images that need text overlaid
      - Mostly black/blank images that need other layers
      - Images that appear to be incomplete or need layering
      - Page backgrounds, textures, watermarks
      - Decorative borders, page ornaments
      - Publisher logos, small icons
      - Repeated design elements
      - Low-quality artifacts from PDF extraction
      - Any image that wouldn't make sense shown standalone to players

      Respond in this exact format:
      CLASSIFICATION: [one of: map, character, monster, item, scene, handout, table, decorative, background, logo, artifact, silhouette, incomplete, other]
      DESCRIPTION: [brief description of the image content, 1-2 sentences]
      KEEP: [YES or NO]
    PROMPT

    base_prompt
  end

  def parse_classification_response(content)
    classification = content.match(/CLASSIFICATION:\s*(.+?)$/i)&.captures&.first&.strip&.downcase || 'unknown'
    description = content.match(/DESCRIPTION:\s*(.+?)(?=KEEP:)/mi)&.captures&.first&.strip || ''
    keep = content.match(/KEEP:\s*(YES|NO)/i)&.captures&.first&.upcase == 'YES'

    {
      classification: classification,
      description: description,
      should_delete: !keep
    }
  end
end
