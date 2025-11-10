class ClassifyImages
  def initialize(pdf, reclassify: false)
    @pdf = pdf
    @reclassify = reclassify
    @service = @pdf.game.user.ai_service
  end

  def call
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
    # Convert image to base64
    image_data = image.download
    base64_image = Base64.strict_encode64(image_data)
    content_type = image.content_type

    begin
      # Build the message with image and prompt
      messages = build_image_message(base64_image, content_type)

      # Get JSON schema for structured output
      tools = [classification_tool_schema]

      # Call the service with structured output
      response = @service.chat(
        messages: messages,
        tools: tools,
        stream: false
      )

      # Extract the structured classification from tool calls
      if response[:tool_calls]&.any?
        tool_call = response[:tool_calls].first
        classification_data = tool_call[:arguments]

        # Update the image metadata
        image.blob.update(
          metadata: image.blob.metadata.merge(
            'classification': classification_data['classification'],
            'description': classification_data['description'],
            'classified_at': Time.current.iso8601
          )
        )
        Rails.logger.info "Classified image #{image.filename}: #{classification_data['classification']}"
      else
        raise "No structured classification returned from API"
      end
    rescue AiService::Error => e
      Rails.logger.error "Failed to classify image #{image.filename}: #{e.detailed_message}"
      # Mark as failed but don't crash
      image.blob.update(
        metadata: image.blob.metadata.merge(
          'classification_error': e.message,
        )
      )
    rescue => e
      Rails.logger.error "Failed to classify image #{image.filename}: #{e.class} - #{e.message}"
      # Mark as failed but don't crash
      image.blob.update(
        metadata: image.blob.metadata.merge(
          'classification_error': e.message,
        )
      )
    end
  end

  def build_image_message(base64_image, content_type)
    # For OpenAI, we use their specific format
    if @provider == :openai
      [
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
      ]
    else
      # For Claude, we use their format with base64 directly
      [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: classification_prompt
            },
            {
              type: "image",
              source: {
                type: "base64",
                media_type: content_type,
                data: base64_image
              }
            }
          ]
        }
      ]
    end
  end

  def classification_prompt
    <<~PROMPT
      You are analyzing an image extracted from a tabletop RPG PDF.

      CONTEXT FROM THE PDF:
      #{@pdf.text_content}

      Use this context to better understand the purpose and content of the image.
      For example:
      - If the PDF is about a specific adventure, images may be maps or NPCs from that adventure
      - If the PDF mentions specific locations, images may depict those locations
      - If the PDF describes monsters or characters, images may be their illustrations
      - Use the text to identify what makes this image valuable or not for players

      Please classify this image and provide a brief description. Use the classify_image tool to return your structured response.

      Image Types to consider:
      - map: Maps, dungeon layouts, floor plans (with labels, keys, and details visible)
      - character: Character portraits (fully rendered, not silhouettes)
      - monster: Monster illustrations (fully rendered, not silhouettes)
      - item: Item illustrations, equipment diagrams (complete illustrations)
      - scene: Scene illustrations that depict story moments (fully rendered scenes)
      - handout: Handouts meant for players (complete and readable)
      - table: Tables, charts with game information (complete with all text)
      - decorative: Decorative elements, borders, ornamental designs
      - background: Background textures or patterns
      - logo: Publisher logos or branding
      - artifact: Scanning artifacts or image processing issues
      - silhouette: Silhouettes or incomplete character/monster outlines
      - incomplete: Incomplete or partial illustrations
      - other: Anything that doesn't fit the above categories
    PROMPT
  end

  def classification_tool_schema
    {
      name: "classify_image",
      description: "Classify an RPG image and provide a description",
      parameters: {
        type: "object",
        properties: {
          classification: {
            type: "string",
            enum: [
              "map", "character", "monster", "item", "scene", "handout",
              "table", "decorative", "background", "logo", "artifact",
              "silhouette", "incomplete", "other"
            ],
            description: "The classification category for the image"
          },
          description: {
            type: "string",
            description: "A brief 1-2 sentence description of the image content"
          }
        },
        required: ["classification", "description"]
      }
    }
  end
end
