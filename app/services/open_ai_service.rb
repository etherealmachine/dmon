class OpenAiService

  def initialize(api_key: nil, model: "gpt-4o-mini")
    @api_key = api_key || ENV['OPENAI_API_KEY']
    @model = model
  end

  # Send a chat request with the given messages and tools
  # @param messages [Array<Hash>] Array of message hashes with :role and :content
  #   Content can be a string or an array of content blocks (text, image_url)
  # @param system_message [String, nil] Optional system message
  # @param tools [Array<Hash>] Array of tool definitions
  # @param stream [Boolean] Whether to stream the response (default: false)
  # @return [Hash] Unified response with :content, :tool_calls, etc.
  def chat(messages:, system_message: nil, tools: [], stream: false, &block)
    # Prepend system message if provided
    full_messages = []
    full_messages << { role: "system", content: system_message } if system_message.present?
    full_messages += messages

    parameters = {
      model: @model,
      messages: full_messages
    }

    # Add tools if provided
    if tools.any?
      parameters[:tools] = format_tools(tools)
      parameters[:tool_choice] = "auto"
    end

    if stream && block_given?
      # Streaming mode
      stream_response(parameters, &block)
    else
      # Non-streaming mode
      response = client.chat(parameters: parameters)
      parse_response(response)
    end
  end

  private

  def client
    @client ||= OpenAI::Client.new(access_token: @api_key)
  end

  # Stream a response and yield chunks as they arrive
  # @param parameters [Hash] API request parameters
  # @yield [Hash] Yields chunks with :type, :content, :tool_calls, etc.
  def stream_response(parameters, &block)
    accumulated_text = ""
    accumulated_tool_calls = {}

    yield({ type: "start" })

    parameters[:stream] = proc { |chunk, _bytesize|
      handle_stream_chunk(chunk, accumulated_text, accumulated_tool_calls, &block)
    }

    client.chat(parameters: parameters)

    # Yield final complete event with accumulated data
    result = {
      type: "complete",
      content: accumulated_text,
      role: "assistant"
    }

    # Convert accumulated_tool_calls hash to array
    if accumulated_tool_calls.any?
      tool_calls_array = accumulated_tool_calls.values.map do |tc|
        {
          id: tc[:id],
          name: tc[:name],
          arguments: JSON.parse(tc[:arguments])
        }
      end
      result[:tool_calls] = tool_calls_array
    end

    yield(result)
  rescue StandardError => e
    yield({ type: "error", error: e.message })
  end

  # Handle streaming chunks from OpenAI
  def handle_stream_chunk(chunk, accumulated_text, accumulated_tool_calls, &block)
    return unless chunk

    # OpenAI sends "data: [DONE]" when stream is complete
    return if chunk == "[DONE]"

    # The chunk might already be parsed as a hash or might be a JSON string
    data = chunk.is_a?(String) ? (JSON.parse(chunk) rescue nil) : chunk
    return unless data

    delta = data.dig("choices", 0, "delta")
    return unless delta

    # Handle content
    if delta["content"]
      accumulated_text << delta["content"]
      yield({ type: "content", content: delta["content"] })
    end

    # Handle tool calls in streaming - OpenAI streams them incrementally
    if delta["tool_calls"]
      delta["tool_calls"].each do |tool_call|
        index = tool_call["index"]

        # Initialize tool call if this is the first chunk for this index
        if tool_call["id"]
          accumulated_tool_calls[index] = {
            id: tool_call["id"],
            name: tool_call.dig("function", "name"),
            arguments: ""
          }
        end

        # Accumulate arguments if present
        if tool_call.dig("function", "arguments")
          accumulated_tool_calls[index][:arguments] << tool_call.dig("function", "arguments")
        end
      end
    end
  rescue JSON::ParserError
    # Ignore parsing errors for partial chunks
  end

  # Format tools into OpenAI's expected format
  # @param tools [Array<Hash>] Tools in unified format
  # @return [Array<Hash>] Tools in OpenAI format
  def format_tools(tools)
    tools.map do |tool|
      {
        type: "function",
        function: {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:parameters]
        }
      }
    end
  end

  # Parse OpenAI response into unified format
  # @param response [Hash] Raw OpenAI API response
  # @return [Hash] Unified response format
  def parse_response(response)
    message = response.dig("choices", 0, "message")

    result = {
      content: message["content"] || "",
      role: "assistant"
    }

    # Parse tool calls if present
    if message["tool_calls"]
      result[:tool_calls] = message["tool_calls"].map do |tool_call|
        {
          id: tool_call["id"],
          name: tool_call["function"]["name"],
          arguments: JSON.parse(tool_call["function"]["arguments"])
        }
      end
    end

    result
  end
end
