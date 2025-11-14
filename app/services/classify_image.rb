class ClassifyImage
  def initialize(image, model, text_context:)
    @image = image
    @model = model
    @text_context = text_context
  end

  def classify
    messages = [
      {
        role: "user",
        content: classification_prompt,
        images: [@image]
      }
    ]

    tools = [classification_tool_schema]

    response = AiService.chat(
      model: @model,
      messages: messages,
      tools: tools,
      stream: false
    )

    if response[:tool_calls]&.any?
      tool_call = response[:tool_calls].first
      classification_data = tool_call[:arguments]

      @image.blob.update(
        metadata: @image.blob.metadata.merge(
          'classification_error' => nil,
          'classification' => classification_data['classification'],
          'description' => classification_data['description'],
          'classified_at' => Time.current.iso8601
        )
      )

      Rails.logger.info "Classified image #{@image.filename}: #{classification_data['classification']}"
    else
      raise "No structured classification returned from API"
    end
  end

  def classification_prompt
    <<~PROMPT
      You are analyzing an image extracted from a tabletop RPG PDF.

      CONTEXT FROM THE PDF:
      #{@text_context}

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
