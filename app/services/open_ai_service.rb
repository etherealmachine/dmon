class OpenAiService
  class Error < StandardError
    attr_reader :original_error, :response_body

    def initialize(message, original_error: nil, response_body: nil)
      super(message)
      @original_error = original_error
      @response_body = response_body
    end

    def detailed_message
      parts = [message]
      parts << "Response body: #{response_body}" if response_body.present?
      parts << "Original error: #{original_error.class} - #{original_error.message}" if original_error
      parts.join("\n")
    end
  end

  def initialize(api_key: nil, model: "gpt-4o-mini")
    @api_key = api_key || ENV['OPENAI_API_KEY']
    @model = model
  end

  # Send a chat request with the given messages and tools
  # @param messages [Array<Hash>] Array of message hashes with :role and :content
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
      parameters[:stream] = proc { |chunk, _bytesize|
        handle_stream_chunk(chunk, &block)
      }
      client.chat(parameters: parameters)
      nil # Return nil since we're yielding chunks
    else
      # Non-streaming mode
      response = client.chat(parameters: parameters)
      parse_response(response)
    end
  rescue Faraday::BadRequestError => e
    response_body = e.response[:body]

    # Parse response body if it's a string
    parsed_body = if response_body.is_a?(String)
      JSON.parse(response_body) rescue response_body
    else
      response_body
    end

    error_message = if parsed_body.is_a?(Hash) && parsed_body.dig("error", "message")
      "OpenAI API request failed: #{parsed_body['error']['message']}"
    else
      "OpenAI API request failed: #{parsed_body}"
    end
    raise Error.new(error_message, original_error: e, response_body: parsed_body)
  rescue StandardError => e
    error_message = "OpenAI API request failed: #{e.message}"
    response_body = nil

    # Try to extract error details if available
    if e.respond_to?(:response) && e.response
      response_body = e.response[:body] rescue nil
    end

    raise Error.new(error_message, original_error: e, response_body: response_body)
  end

  private

  def client
    @client ||= OpenAI::Client.new(access_token: @api_key)
  end

  # Handle streaming chunks from OpenAI
  def handle_stream_chunk(chunk, &block)
    return unless chunk

    # OpenAI sends "data: [DONE]" when stream is complete
    return if chunk == "[DONE]"

    data = JSON.parse(chunk) rescue nil
    return unless data

    delta = data.dig("choices", 0, "delta")
    return unless delta

    if delta["content"]
      yield({ type: "content", content: delta["content"] })
    end

    # Handle tool calls in streaming
    if delta["tool_calls"]
      delta["tool_calls"].each do |tool_call|
        yield({
          type: "tool_call",
          tool_call: {
            id: tool_call["id"],
            name: tool_call.dig("function", "name"),
            arguments: tool_call.dig("function", "arguments")
          }
        })
      end
    end

    # Check if stream is done
    finish_reason = data.dig("choices", 0, "finish_reason")
    if finish_reason
      yield({ type: "complete", finish_reason: finish_reason })
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
