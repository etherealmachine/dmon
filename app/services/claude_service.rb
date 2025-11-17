require "anthropic"

class ClaudeService

  def initialize(api_key: nil, model: "claude-3-5-sonnet-20241022", user: nil)
    @api_key = api_key || ENV['ANTHROPIC_API_KEY']
    @model = model
    @user = user
    @client = Anthropic::Client.new(api_key: @api_key)
  end

  # Send a chat request with the given messages and tools
  # @param messages [Array<Hash>] Array of message hashes with :role and :content
  #   Content can be a string or an array of content blocks (text, image)
  # @param system_message [String, nil] Optional system message
  # @param tools [Array<Hash>] Array of tool definitions
  # @param stream [Boolean] Whether to stream the response (default: false)
  # @return [Hash] Unified response with :content, :tool_calls, etc.
  def chat(messages:, system_message: nil, tools: [], stream: false, &block)
    parameters = {
      model: @model,
      max_tokens: 16384,
      messages: format_messages(messages)
    }

    # Add system message if provided (Claude uses top-level system parameter)
    parameters[:system] = system_message if system_message.present?

    # Add tools if provided
    parameters[:tools] = format_tools(tools) if tools.any?

    if stream && block_given?
      # Streaming mode
      parameters[:stream] = true
      stream_response(parameters, &block)
    else
      # Non-streaming mode
      response = @client.messages.create(**parameters)
      parse_response(response)
    end
  end

  private

  # Stream a response and yield chunks as they arrive
  # @param parameters [Hash] API request parameters
  # @yield [Hash] Yields chunks with :type, :content, :tool_calls, etc.
  def stream_response(parameters, &block)
    accumulated_text = ""
    accumulated_tool_calls = []
    current_tool_use = nil
    usage_data = { input_tokens: 0, output_tokens: 0 }

    # Remove stream parameter as it's implicit in the .stream() method
    parameters.delete(:stream)

    stream = @client.messages.stream(**parameters)

    stream.each do |event|
      # Skip helper/convenience events - we only want the raw events
      next unless event.class.name.start_with?("Anthropic::Models::Raw") || event.class.name.include?("::MessageStopEvent") || event.class.name.include?("::ContentBlockStopEvent")

      event_type = event.type.to_s
      case event_type
      when "message_start"
        # Message started - capture initial usage data
        if event.message&.usage
          usage_data[:input_tokens] = event.message.usage.input_tokens || 0
          usage_data[:output_tokens] = event.message.usage.output_tokens || 0
        end
        yield({ type: "start" })
      when "content_block_start"
        # New content block started
        block_type = event.content_block.type.to_s
        if block_type == "tool_use"
          current_tool_use = {
            id: event.content_block.id,
            name: event.content_block.name,
            arguments: ""
          }
        end
      when "content_block_delta"
        # Content chunk received
        delta_type = event.delta.type.to_s
        if delta_type == "text_delta" || delta_type == "text"
          text = event.delta.text
          accumulated_text += text
          yield({ type: "content", content: text })
        elsif delta_type == "input_json_delta" || delta_type == "input_json"
          # Tool use input being streamed
          current_tool_use[:arguments] += event.delta.partial_json if current_tool_use
        end
      when "content_block_stop"
        # Content block finished
        if current_tool_use
          # Parse the accumulated JSON arguments
          current_tool_use[:arguments] = JSON.parse(current_tool_use[:arguments])
          accumulated_tool_calls << current_tool_use
          current_tool_use = nil
        end
      when "message_delta"
        # Additional message metadata - update usage if present
        if event.usage
          usage_data[:output_tokens] = event.usage.output_tokens || usage_data[:output_tokens]
        end
      when "message_stop"
        # Message complete - track token usage
        if @user
          @user.track_token_usage(
            model: @model,
            input_tokens: usage_data[:input_tokens],
            output_tokens: usage_data[:output_tokens]
          )
        end

        result = {
          type: "complete",
          content: accumulated_text,
          role: "assistant"
        }
        result[:tool_calls] = accumulated_tool_calls if accumulated_tool_calls.any?
        yield(result)
      when "error"
        yield({ type: "error", error: event.error })
      end
    end
  rescue StandardError => e
    yield({ type: "error", error: e.message })
  end

  # Format messages into Claude's expected format
  # Claude doesn't support system messages in the messages array
  # @param messages [Array<Hash>] Messages in unified format
  # @return [Array<Hash>] Messages in Claude format
  def format_messages(messages)
    # Access hash keys as both symbols and strings for flexibility
    messages.reject { |m| (m[:role] || m["role"]) == "system" }.map do |message|
      role = message[:role] || message["role"]
      content = message[:content] || message["content"]
      tool_calls = message[:tool_calls] || message["tool_calls"]
      tool_call_id = message[:tool_call_id] || message["tool_call_id"]

      formatted = {
        role: role,
        content: []
      }

      # Handle tool results (from tool role)
      if role == "tool"
        formatted[:role] = "user" # Claude expects tool results in user messages
        formatted[:content] = [{
          type: "tool_result",
          tool_use_id: tool_call_id,
          content: content
        }]
      else
        # Handle content array (already formatted with text/image blocks)
        if content.is_a?(Array)
          formatted[:content] = content
        # Handle string content
        elsif content.present?
          formatted[:content] << {
            type: "text",
            text: content
          }
        end

        # Handle tool calls (from assistant)
        if tool_calls
          tool_calls.each do |tool_call|
            # Extract name from either direct field or function wrapper
            name = tool_call[:function]&.dig("name") || tool_call["function"]&.dig("name") || tool_call[:name] || tool_call["name"]

            # Extract arguments - they might be a JSON string or already parsed
            arguments = tool_call[:function]&.dig("arguments") || tool_call["function"]&.dig("arguments") || tool_call[:arguments] || tool_call["arguments"]
            input = arguments.is_a?(String) ? JSON.parse(arguments) : arguments

            formatted[:content] << {
              type: "tool_use",
              id: tool_call[:id] || tool_call["id"],
              name: name,
              input: input
            }
          end
        end

        # Claude requires content to be a simple string if there's only text
        if formatted[:content].length == 1 && formatted[:content][0][:type] == "text"
          formatted[:content] = formatted[:content][0][:text]
        end
      end

      formatted
    end
  end

  # Format tools into Claude's expected format
  # @param tools [Array<Hash>] Tools in unified format
  # @return [Array<Hash>] Tools in Claude format
  def format_tools(tools)
    tools.map do |tool|
      {
        name: tool[:name],
        description: tool[:description],
        input_schema: tool[:parameters] # Claude uses input_schema instead of parameters
      }
    end
  end

  # Parse Claude response into unified format
  # @param response [Anthropic::Message] Raw Claude API response
  # @return [Hash] Unified response format
  def parse_response(response)
    result = {
      content: "",
      role: "assistant"
    }

    # Claude returns content as an array of content blocks
    content_blocks = response.content || []

    text_blocks = []
    tool_calls = []

    content_blocks.each do |block|
      case block.type
      when "text"
        text_blocks << block.text
      when "tool_use"
        tool_calls << {
          id: block.id,
          name: block.name,
          arguments: block.input
        }
      end
    end

    result[:content] = text_blocks.join("\n")
    result[:tool_calls] = tool_calls if tool_calls.any?

    # Track token usage if user is present
    # Claude provides usage in the response.usage field
    if @user && response.usage
      @user.track_token_usage(
        model: @model,
        input_tokens: response.usage.input_tokens || 0,
        output_tokens: response.usage.output_tokens || 0
      )
    end

    result
  end
end
