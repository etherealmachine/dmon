# == Schema Information
#
# Table name: game_agents
#
#  id                   :bigint           not null, primary key
#  conversation_history :json
#  plan                 :json
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  game_id              :bigint           not null
#
# Indexes
#
#  index_game_agents_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#

# Require tool classes
require_dependency Rails.root.join("app", "tools", "game_agent", "create_game_note_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "search_game_notes_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "read_game_note_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "edit_game_note_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "roll_dice_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "call_note_action_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "set_note_stats_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "update_note_stats_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "update_plan_tool")
require_dependency Rails.root.join("app", "tools", "game_agent", "delete_game_note_tool")

class GameAgent < ApplicationRecord
  belongs_to :game

  # Initialize conversation history as empty array if nil
  after_initialize :ensure_conversation_history
  after_initialize :ensure_plan

  # Get all available tools for this game agent
  def tools
    @tools ||= [
      GameAgentTools::CreateGameNoteTool.new(game),
      GameAgentTools::SearchGameNotesTool.new(game),
      GameAgentTools::ReadGameNoteTool.new(game),
      GameAgentTools::EditGameNoteTool.new(game),
      GameAgentTools::RollDiceTool.new(game),
      GameAgentTools::CallNoteActionTool.new(game),
      GameAgentTools::SetNoteStatsTool.new(game),
      GameAgentTools::UpdateNoteStatsTool.new(game),
      GameAgentTools::UpdatePlanTool.new(self), # Needs agent instance for plan field
      GameAgentTools::DeleteGameNoteTool.new(game)
    ]
  end

  # Get tool definitions for API calls (converts RubyLLM::Tool to unified format)
  def tool_definitions
    tools.map do |tool|
      {
        name: tool.name,
        description: tool.description,
        parameters: tool.params_schema || {}
      }
    end
  end

  # Execute a tool by name using the tool class
  def execute_tool_class(tool_name, arguments)
    tool = tools.find { |t| t.name == tool_name }

    if tool
      tool.execute(**arguments.transform_keys(&:to_sym))
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  rescue => e
    Rails.logger.error "Tool execution error: #{e.class} - #{e.message}"
    { error: e.message }
  end

  def call(input, context_items: [], &block)
    # Store input and context items for slash commands and context to access
    @current_input = input
    @context_items = context_items

    # Check for slash commands
    if input.strip.match?(/^\/(\w+)/)
      command_name = input.strip.match(/^\/(\w+)/)[1]
      command_method = "#{command_name}_command"

      if respond_to?(command_method, true)
        result = send(command_method)
        if result
          yield({ type: "content", content: result.to_json }) if block_given?
          add_message(role: "assistant", content: result.to_json)
        end
        return result
      end
      # If command doesn't exist, fall through to normal processing
    end

    transaction do
      unless input.empty?
        add_message(role: "user", content: input)
        yield({ type: "user_message", content: input }) if block_given?
      end

      # Determine if we should stream
      stream = block_given?

      # Make initial API call with tools
      accumulated_response = { content: "", tool_calls: [] }

      if stream
        # Streaming mode
        AiService.chat(
          user: game.user,
          messages: conversation_history,
          system_message: context_string,
          tools: tool_definitions,
          stream: true
        ) do |chunk|
          case chunk[:type]
          when "start"
            yield({ type: "assistant_start" })
          when "content"
            accumulated_response[:content] += chunk[:content]
            yield(chunk)
          when "complete"
            accumulated_response[:tool_calls] = chunk[:tool_calls] if chunk[:tool_calls]
          when "error"
            yield(chunk)
            raise StandardError, chunk[:error]
          end
        end
      else
        # Non-streaming mode
        response = AiService.chat(
          user: game.user,
          messages: conversation_history,
          system_message: context_string,
          tools: tool_definitions
        )
        accumulated_response[:content] = response[:content] || ""
        accumulated_response[:tool_calls] = response[:tool_calls] if response[:tool_calls]
      end

      # Handle tool calls if present
      if accumulated_response[:tool_calls]&.any?
        # Add assistant message with tool calls to history
        add_message(
          role: "assistant",
          content: accumulated_response[:content] || "",
          tool_calls: accumulated_response[:tool_calls].map { |tc|
            {
              "id" => tc[:id],
              "type" => "function",
              "function" => {
                "name" => tc[:name],
                "arguments" => tc[:arguments].to_json
              }
            }
          }
        )

        yield({ type: "tool_calls_start", count: accumulated_response[:tool_calls].length }) if stream

        # Execute each tool call
        accumulated_response[:tool_calls].each do |tool_call|
          yield({ type: "tool_call", name: tool_call[:name], arguments: tool_call[:arguments] }) if stream

          tool_result = execute_tool_class(tool_call[:name], tool_call[:arguments])

          yield({ type: "tool_result", name: tool_call[:name], result: tool_result }) if stream

          # Add tool result to conversation history
          add_message(
            role: "tool",
            content: tool_result.to_json,
            tool_call_id: tool_call[:id]
          )
        end

        yield({ type: "tool_calls_complete" }) if stream
        yield({ type: "assistant_start" }) if stream

        # Make final API call after tool execution
        final_accumulated = ""

        if stream
          # Stream final response
          AiService.chat(
            user: game.user,
            messages: conversation_history,
            system_message: context_string,
            tools: tool_definitions,
            stream: true
          ) do |chunk|
            case chunk[:type]
            when "content"
              final_accumulated += chunk[:content]
              yield(chunk)
            when "complete"
              # Nothing special needed here
            when "error"
              yield(chunk)
              raise StandardError, chunk[:error]
            end
          end
        else
          # Non-streaming final response
          final_response = AiService.chat(
            user: game.user,
            messages: conversation_history,
            system_message: context_string,
            tools: tool_definitions
          )
          final_accumulated = final_response[:content] || ""
        end

        add_message(role: "assistant", content: final_accumulated)
      else
        # No tool calls, just add the response
        add_message(role: "assistant", content: accumulated_response[:content] || "")
      end
    rescue AiService::Error => e
      Rails.logger.error "AI Service error: #{e.detailed_message}"
      yield({ type: "error", error: e.detailed_message }) if block_given?
      raise e
    end
  end

  def clear!
    self.conversation_history = []
    self.plan = []
    save!
  end


  private

  def clear_command
    clear!
    nil
  end

  def roll_command
    # The input should be "/roll 2d6+3" or similar
    # We need to extract everything after "/roll "
    input = @current_input
    dice_notation = input.strip.sub(/^\/roll\s+/, "")

    if dice_notation.blank?
      return { command: "roll", success: false, error: "Please provide dice notation (e.g., /roll 1d20, /roll 2d6+3)" }
    end

    # Use the RollDiceTool class
    roll_tool = tools.find { |t| t.is_a?(GameAgentTools::RollDiceTool) }
    result = roll_tool.execute(dice_notation: dice_notation)
    { command: "roll", **result }
  end

  def ensure_conversation_history
    self.conversation_history ||= []
  end

  def ensure_plan
    self.plan ||= []
  end

  def context_string
    context_parts = context_messages.map { |msg| msg[:content] }
    parts = [initial_prompt] + context_parts

    # Add plan if it exists and is not empty
    if plan.present? && plan.any?
      plan_text = "## Current Plan\n\n"
      plan.each_with_index do |item, index|
        status = item["completed"] ? "[x]" : "[ ]"
        plan_text += "#{index}. #{status} #{item["description"]}\n"
      end
      parts << plan_text
    end

    parts << final_prompt

    parts.join("\n\n")
  end

  def add_message(role:, content:, tool_calls: nil, tool_call_id: nil)
    self.conversation_history ||= []
    message = { "role" => role, "content" => content }
    message["tool_calls"] = tool_calls if tool_calls
    message["tool_call_id"] = tool_call_id if tool_call_id
    self.conversation_history << message
    save!
  end

  def context_messages
    # Start with context-type notes
    context_notes = game.game_notes.where(note_type: "context")

    # Add dynamically selected context items (passed via GlobalID)
    selected_items = (@context_items || []).map do |gid|
      GlobalID::Locator.locate(gid) rescue nil
    end.compact

    # Combine and format all context items
    (context_notes + selected_items).uniq.map do |item|
      {
        role: "system",
        content: item.context
      }
    end
  end

  def initial_prompt
    <<~PROMPT
      You are a helpful assistant for a tabletop RPG adventure module.

      You have access to the adventure's content below:

      #{game.pdfs.map(&:text_content).join("\n\n")}

      Your role is to answer questions about this adventure module.
      You can help with:
      - Understanding the plot, characters, and locations
      - Finding specific information in the adventure
      - Clarifying rules or mechanics mentioned in the adventure
      - Providing context or background information

      You have access to tools that let you:
      - Create notes to save important information for later reference
      - Roll dice using standard RPG notation (e.g., '1d20', '2d6', '4d8+3')

      Use these tools when appropriate to help the user manage their game session.
      Be helpful, accurate, and concise. If you don't know something or it's not in the adventure content, say so.
    PROMPT
  end

  def final_prompt
    <<~PROMPT
      For multi-step tasks, use the update_plan tool to track progress.
      Update the plan to show what has been completed and what remains to be done.
      Each plan item should have:
      - "description": A clear description of the task
      - "completed": true if done, false if not yet done
    PROMPT
  end
end
