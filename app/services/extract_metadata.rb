class ExtractMetadata
  def initialize(pdf, api_key: nil, model: "gpt-5-nano")
    @pdf = pdf
    @api_key = api_key
    @model = model
  end

  def call
    raise "No text content available" unless @pdf.text_content.present?

    extract_metadata
  end

  private

  def extract_metadata
    # Use OpenAI to analyze and extract metadata
    parsed = analyze_with_openai(@pdf.text_content)

    # Update the adventure with extracted metadata
    @pdf.update(
      name: parsed[:title],
      description: parsed[:description]
    )

    Rails.logger.info "Extracted metadata for PDF ##{@pdf.id}: #{parsed[:title]}"
  end

  def analyze_with_openai(text_content)
    response = AiService.chat(
      model: @model,
      messages: [
        {
          role: "user",
          content: metadata_extraction_prompt(text_content)
        }
      ],
      api_key: @api_key
    )

    content = response[:content] || ""
    parse_metadata_response(content)
  rescue AiService::Error => e
    Rails.logger.error "AI service error while extracting metadata: #{e.detailed_message}"
    raise
  end

  def metadata_extraction_prompt(text_content)
    <<~PROMPT
      You are analyzing text extracted from a tabletop RPG PDF.

      Your task is to extract:
      1. A clean, concise title for the PDF
      2. A compelling 2-3 sentence description that would entice players

      Guidelines for TITLE:
      - Remove extraneous credits, author names, and level ranges
      - Keep the core PDF name
      - Make it clean and readable
      - Example: "An Adventure for 4-6 Characters Levels 0-1 TREASURE HUNT by Aaron Allston" → "Treasure Hunt"

      Guidelines for DESCRIPTION:
      - Write 2-3 sentences that capture the essence and hook of the PDF
      - Focus on what makes it interesting and unique
      - Be engaging and evocative
      - Avoid technical details like "for a DM and 4-6 characters"
      - Make it sound exciting!

      Here is the extracted text from the PDF:

      #{text_content}

      Respond in this exact format:
      TITLE: [clean PDF title]
      DESCRIPTION: [2-3 sentence compelling description]
    PROMPT
  end

  def parse_metadata_response(content)
    title = content.match(/TITLE:\s*(.+?)$/i)&.captures&.first&.strip || 'Untitled PDF'
    description = content.match(/DESCRIPTION:\s*(.+?)$/mi)&.captures&.first&.strip || ''

    {
      title: title,
      description: description
    }
  end
end
