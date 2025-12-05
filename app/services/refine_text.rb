class RefineText
  def initialize(pdf, user: nil, api_key: nil, model: nil)
    @pdf = pdf
    @user = user || pdf.game.user
    @api_key = api_key
    @model = model
  end

  def call
    raise "No text content available" unless @pdf.text_content.present?

    refine_text
  end

  private

  CHUNK_SIZE = 10_000
  OVERLAP_SIZE = 1_000
  CONTEXT_SIZE = 1_000

  def refine_text
    # Get the raw text content
    raw_text = @pdf.text_content

    # Process text in chunks
    refined_content = process_in_chunks(raw_text)

    # Save the refined content to the text_content column
    @pdf.update!(text_content: refined_content)

    Rails.logger.info "Refined text for PDF ##{@pdf.id}"
  end

  def process_in_chunks(raw_text)
    chunks = create_chunks(raw_text)
    accumulated_markdown = ""

    chunks.each_with_index do |chunk, index|
      Rails.logger.info "Processing chunk #{index + 1}/#{chunks.length} for PDF ##{@pdf.id}"

      # Get context from previously processed markdown
      markdown_context = get_markdown_context(accumulated_markdown)

      # Process this chunk
      chunk_result = refine_chunk_with_openai(chunk, markdown_context, index, chunks.length)

      # Append to accumulated markdown
      accumulated_markdown += chunk_result
    end

    accumulated_markdown
  end

  def create_chunks(text)
    chunks = []
    position = 0

    while position < text.length
      # Calculate chunk end position
      chunk_end = [position + CHUNK_SIZE, text.length].min

      # Extract chunk with overlap from previous chunk
      chunk_start = [position - OVERLAP_SIZE, 0].max
      chunk = text[chunk_start...chunk_end]

      chunks << {
        text: chunk,
        is_first: position == 0,
        is_last: chunk_end >= text.length
      }

      # Move position forward (accounting for overlap)
      position += CHUNK_SIZE
    end

    chunks
  end

  def get_markdown_context(accumulated_markdown)
    return "" if accumulated_markdown.empty?

    # Get last CONTEXT_SIZE characters of accumulated markdown
    if accumulated_markdown.length <= CONTEXT_SIZE
      accumulated_markdown
    else
      accumulated_markdown[-CONTEXT_SIZE..-1]
    end
  end

  def refine_chunk_with_openai(chunk, markdown_context, chunk_index, total_chunks)
    chat = RubyLLM.chat(model: @model || @user.preferred_model)
    response = chat.ask(refine_chunk_prompt(chunk, markdown_context, chunk_index, total_chunks))

    response.content || chunk[:text]
  rescue => e
    Rails.logger.error "AI service error while refining chunk: #{e.class} - #{e.message}"
    raise
  end

  def refine_chunk_prompt(chunk, markdown_context, chunk_index, total_chunks)
    is_first = chunk[:is_first]
    is_last = chunk[:is_last]

    context_section = unless is_first
      <<~CONTEXT
        IMPORTANT CONTEXT - Here is the last portion of the markdown generated so far:
        ```
        #{markdown_context}
        ```

        Continue from where the previous chunk left off. Maintain continuity with the existing markdown.
      CONTEXT
    else
      ""
    end

    position_note = if is_first
      "This is the FIRST chunk. Start fresh with the document."
    elsif is_last
      "This is the LAST chunk. Make sure to properly conclude the document."
    else
      "This is a MIDDLE chunk. The text may start or end mid-sentence due to chunking."
    end

    <<~PROMPT
      You are processing text extracted from a tabletop RPG PDF. This is chunk #{chunk_index + 1} of #{total_chunks}.

      Your task is to:
      1. Remove extraction artifacts (weird spacing, broken words, OCR errors)
      2. Reconstruct proper paragraph structure
      3. Identify and properly format sections with markdown headers (##, ###, etc.)
      4. Preserve important information like tables, stat blocks, and lists
      5. Format tables using markdown table syntax where appropriate
      6. Use bullet points (-) or numbered lists (1.) for list items
      7. Preserve author credits, copyright information, and attribution
      8. Fix obvious typos and spacing issues
      9. Use **bold** for emphasis where appropriate (monster names, important terms)
      10. Use *italic* for flavor text, quotes, or descriptive passages

      Guidelines:
      - Do NOT add new content or make up information
      - Do NOT remove substantive content
      - Focus on cleaning formatting and making the text readable
      - Maintain the original structure and flow of the document
      - If something is unclear, preserve it rather than guessing
      - Keep the tone and style of the original text
      - Format the output as clean, well-structured markdown

      #{context_section}

      #{position_note}

      Here is the text to process:

      #{chunk[:text]}

      Omit ```markdown``` tags from the output.
      Omit any commentary or explanation about the text being processed (e.g. "This is the first chunk", "This is the last chunk", "This is a middle chunk").
      Please provide ONLY the new markdown content to append (do not repeat the context).
    PROMPT
  end
end
