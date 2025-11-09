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
class GameAgent < ApplicationRecord
  belongs_to :game

  # Initialize conversation history as empty array if nil
  after_initialize :ensure_conversation_history
  after_initialize :ensure_plan

  attr_accessor :model
  ALLOWED_MODELS = %w[gpt-5 gpt-5-nano claude-haiku-4-5-20251001].freeze

  def model
    @model ||= ALLOWED_MODELS.first
  end

  def ai_service
    if !ALLOWED_MODELS.include?(model)
      raise "Invalid model: #{model}"
    end
    if model.starts_with?('claude')
      @ai_service ||= ClaudeService.new(model: model)
    else
      @ai_service ||= OpenAiService.new(model: model)
    end
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
      add_message(role: "user", content: input)
      yield({ type: "user_message", content: input }) if block_given?

      # Determine if we should stream
      stream = block_given?

      # Make initial API call with tools
      accumulated_response = { content: "", tool_calls: [] }

      if stream
        # Streaming mode
        ai_service.chat(
          messages: conversation_history,
          system_message: context_string,
          tools: unified_tool_definitions,
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
        response = ai_service.chat(
          messages: conversation_history,
          system_message: context_string,
          tools: unified_tool_definitions
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

          tool_result = execute_tool(tool_call[:name], tool_call[:arguments])

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
          ai_service.chat(
            messages: conversation_history,
            system_message: context_string,
            tools: unified_tool_definitions,
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
          final_response = ai_service.chat(
            messages: conversation_history,
            system_message: context_string,
            tools: unified_tool_definitions
          )
          final_accumulated = final_response[:content] || ""
        end

        add_message(role: "assistant", content: final_accumulated)
      else
        # No tool calls, just add the response
        add_message(role: "assistant", content: accumulated_response[:content] || "")
      end
    rescue OpenAiService::Error, ClaudeService::Error => e
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

  def unified_tool_definitions
    [
      {
        name: "create_game_note",
        description: "Create a new note for this game. Use this to save important information, reminders, or observations that should be persisted. Optionally attach actions (like dice rolls) that can be executed later, or set initial stats.",
        parameters: {
            type: "object",
            properties: {
              content: {
                type: "string",
                description: "The note contents - markdown is supported"
              },
              note_type: {
                type: "string",
                enum: GameNote.note_types.map(&:second),
                description: "The type of note",
              },
              stats: {
                type: "object",
                description: "Optional object containing stat key-value pairs (e.g., {\"HP\": 45, \"AC\": 18})",
                additionalProperties: true
              },
              actions: {
                type: "array",
                description: "Optional array of actions that can be executed later (e.g., dice rolls for attacks or abilities)",
                items: {
                  type: "object",
                  properties: {
                    type: {
                      type: "string",
                      enum: ["roll"],
                      description: "The type of action - currently only 'roll' is supported"
                    },
                    name: {
                      type: "string",
                      description: "Name of the action (e.g., 'Attack Roll', 'Damage Roll')"
                    },
                    description: {
                      type: "string",
                      description: "Description of what this action does"
                    },
                    args: {
                      type: "object",
                      description: "Arguments for the action. For 'roll' type, this should contain dice notation and optional modifiers",
                      properties: {
                        dice_notation: {
                          type: "string",
                          description: "Dice notation (e.g., '1d20+4', '2d6')"
                        },
                        advantage: {
                          type: "boolean",
                          description: "For d20 rolls, roll twice and take higher"
                        },
                        disadvantage: {
                          type: "boolean",
                          description: "For d20 rolls, roll twice and take lower"
                        }
                      }
                    }
                  },
                  required: ["type", "args"]
                }
              }
            },
            required: ["content", "note_type"]
          }
      },
      {
        name: "search_game_notes",
        description: "Search for game notes by keyword or filter by note type. Returns a list of matching notes with their IDs, content, and metadata.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Optional search query to filter notes by content"
            },
            note_type: {
              type: "string",
              enum: GameNote.note_types.map(&:second),
              description: "Optional filter by note type",
            }
          },
          required: []
        }
      },
      {
        name: "read_game_note",
        description: "Read the full details of a specific game note by its ID. Returns the complete note content including input, output, type, and timestamps.",
        parameters: {
          type: "object",
          properties: {
            note_id: {
              type: "integer",
              description: "The ID of the note to read"
            }
          },
          required: ["note_id"]
        }
      },
      {
        name: "edit_game_note",
        description: "Edit an existing game note by its ID. Can update the content, note type, stats, or actions fields.",
        parameters: {
            type: "object",
            properties: {
              note_id: {
                type: "integer",
                description: "The ID of the note to edit"
              },
              content: {
                type: "string",
                description: "Updated note content (markdown supported)"
              },
              note_type: {
                type: "string",
                enum: GameNote.note_types.map(&:second),
                description: "Updated note type",
              },
              stats: {
                type: "object",
                description: "Updated stats object (replaces existing stats). Pass empty object {} to clear all stats.",
                additionalProperties: true
              },
              actions: {
                type: "array",
                description: "Updated array of actions that can be executed later (replaces existing actions)",
                items: {
                  type: "object",
                  properties: {
                    type: {
                      type: "string",
                      enum: ["roll"],
                      description: "The type of action - currently only 'roll' is supported"
                    },
                    name: {
                      type: "string",
                      description: "Name of the action (e.g., 'Attack Roll', 'Damage Roll')"
                    },
                    description: {
                      type: "string",
                      description: "Description of what this action does"
                    },
                    args: {
                      type: "object",
                      description: "Arguments for the action. For 'roll' type, this should contain dice notation and optional modifiers",
                      properties: {
                        dice_notation: {
                          type: "string",
                          description: "Dice notation (e.g., '1d20+4', '2d6')"
                        },
                        advantage: {
                          type: "boolean",
                          description: "For d20 rolls, roll twice and take higher"
                        },
                        disadvantage: {
                          type: "boolean",
                          description: "For d20 rolls, roll twice and take lower"
                        }
                      }
                    }
                  },
                  required: ["type", "args"]
                }
              }
            },
            required: ["note_id"]
          }
      },
      {
        name: "roll_dice",
        description: "Roll dice using standard RPG notation (e.g., '1d20', '2d6', '4d8+3'). Supports modifiers like +/- and advantage/disadvantage for d20 rolls.",
        parameters: {
          type: "object",
          properties: {
            dice_notation: {
              type: "string",
              description: "The dice to roll in standard notation (e.g., '1d20', '2d6', '4d8+3', '1d20+5')"
            },
            advantage: {
              type: "boolean",
              description: "For d20 rolls, roll twice and take the higher result"
            },
            disadvantage: {
              type: "boolean",
              description: "For d20 rolls, roll twice and take the lower result"
            },
            description: {
              type: "string",
              description: "Optional description of what the roll is for (e.g., 'attack roll', 'damage')"
            }
          },
          required: ["dice_notation"]
        }
      },
      {
        name: "call_note_action",
        description: "Execute an action attached to a game note. Actions are pre-defined operations (like dice rolls) that can be triggered. The result is added to the note's action history.",
        parameters: {
          type: "object",
          properties: {
            note_id: {
              type: "integer",
              description: "The ID of the note containing the action"
            },
            action_index: {
              type: "integer",
              description: "The index of the action to execute (0-based, so first action is 0, second is 1, etc.)"
            }
          },
          required: ["note_id", "action_index"]
        }
      },
      {
        name: "set_note_stats",
        description: "Set or update stats (key-value pairs) on a game note. Stats are useful for tracking numeric values like HP, AC, ability scores, or any other game-relevant data. This replaces all existing stats on the note.",
        parameters: {
          type: "object",
          properties: {
            note_id: {
              type: "integer",
              description: "The ID of the note to update"
            },
            stats: {
              type: "object",
              description: "Object containing stat key-value pairs (e.g., {\"HP\": 45, \"AC\": 18, \"STR\": 16}). Values can be numbers or strings.",
              additionalProperties: true
            }
          },
          required: ["note_id", "stats"]
        }
      },
      {
        name: "update_note_stats",
        description: "Update specific stats on a game note without replacing all stats. Only the provided stat keys will be updated or added, existing stats not mentioned will remain unchanged.",
        parameters: {
          type: "object",
          properties: {
            note_id: {
              type: "integer",
              description: "The ID of the note to update"
            },
            stats: {
              type: "object",
              description: "Object containing stat key-value pairs to update (e.g., {\"HP\": 30}). Values can be numbers or strings.",
              additionalProperties: true
            }
          },
          required: ["note_id", "stats"]
        }
      },
      {
        name: "update_plan",
        description: "Update the current plan with new items or mark items as completed. This helps track progress on multi-step tasks.",
        parameters: {
          type: "object",
          properties: {
            items: {
              type: "array",
              description: "Array of plan items (replaces the current plan)",
              items: {
                type: "object",
                properties: {
                  description: {
                    type: "string",
                    description: "Description of what needs to be done or what was done"
                  },
                  completed: {
                    type: "boolean",
                    description: "Whether this item is completed (true) or still pending (false)"
                  }
                },
                required: ["description", "completed"]
              }
            }
          },
          required: ["items"]
        }
      },
      {
        name: "delete_game_note",
        description: "Delete a game note by its ID. This permanently removes the note and cannot be undone.",
        parameters: {
          type: "object",
          properties: {
            note_id: {
              type: "integer",
              description: "The ID of the note to delete"
            }
          },
          required: ["note_id"]
        }
      }
    ]
  end

  private

  def clear_command
    clear!
    nil
  end

  def roll_command
    # The input should be "/roll 2d6+3" or similar
    # We need to extract everything after "/roll "
    input = @current_input # We'll need to store this
    dice_notation = input.strip.sub(/^\/roll\s+/, "")

    if dice_notation.blank?
      return { command: "roll", success: false, error: "Please provide dice notation (e.g., /roll 1d20, /roll 2d6+3)" }
    end

    result = roll_dice_tool({ "dice_notation" => dice_notation })
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

  def execute_tool(tool_name, arguments)
    # Convert tool name to method name (e.g., "create_game_note" -> "create_game_note_tool")
    method_name = "#{tool_name}_tool"

    # Check if the method exists and is a private method
    if respond_to?(method_name, true)
      send(method_name, arguments)
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  rescue => e
    Rails.logger.error "Tool execution error: #{e.class} - #{e.message}"
    { error: e.message }
  end

  def create_game_note_tool(arguments)
    note_params = {
      content: arguments["content"],
      note_type: arguments["note_type"]
    }

    # Add stats if provided
    note_params[:stats] = arguments["stats"] if arguments["stats"].present?

    # Add actions if provided
    note_params[:actions] = arguments["actions"] if arguments["actions"].present?

    note = game.game_notes.create!(note_params)

    result = { success: true, note_id: note.id, message: "Note created successfully" }
    result[:stats] = note.stats if note.stats.present?
    result[:actions_count] = note.actions.length if note.actions.present?
    result
  end

  def search_game_notes_tool(arguments)
    notes = game.game_notes

    # Filter by note type if provided
    notes = notes.where(note_type: arguments["note_type"]) if arguments["note_type"].present?

    # Filter by query if provided (search in content)
    if arguments["query"].present?
      query = arguments["query"]
      notes = notes.where(
        "content ILIKE ?",
        "%#{query}%"
      )
    end

    # Order by most recent first
    notes = notes.order(created_at: :desc)

    {
      success: true,
      count: notes.count,
      notes: notes.map { |note|
        note_data = {
          id: note.id,
          content: note.content,
          note_type: note.note_type,
          created_at: note.created_at,
          updated_at: note.updated_at
        }
        note_data[:stats] = note.stats if note.stats.present?
        note_data
      }
    }
  end

  def read_game_note_tool(arguments)
    note = game.game_notes.find_by(id: arguments["note_id"])

    if note
      note_data = {
        id: note.id,
        content: note.content,
        note_type: note.note_type,
        created_at: note.created_at,
        updated_at: note.updated_at
      }
      note_data[:stats] = note.stats if note.stats.present?
      note_data[:actions] = note.actions if note.actions.present?
      note_data[:history] = note.history if note.history.present?

      {
        success: true,
        note: note_data
      }
    else
      {
        success: false,
        error: "Note with ID #{arguments['note_id']} not found"
      }
    end
  end

  def edit_game_note_tool(arguments)
    note = game.game_notes.find_by(id: arguments["note_id"])

    unless note
      return {
        success: false,
        error: "Note with ID #{arguments['note_id']} not found"
      }
    end

    # Update only the fields that are provided
    update_params = {}
    update_params[:content] = arguments["content"] if arguments["content"].present?
    update_params[:note_type] = arguments["note_type"] if arguments["note_type"].present?
    update_params[:stats] = arguments["stats"] if arguments.key?("stats")
    update_params[:actions] = arguments["actions"] if arguments.key?("actions")

    if update_params.empty?
      return {
        success: false,
        error: "No fields provided to update"
      }
    end

    note.update!(update_params)

    result = {
      success: true,
      message: "Note updated successfully",
      note: {
        id: note.id,
        content: note.content,
        note_type: note.note_type,
        created_at: note.created_at,
        updated_at: note.updated_at
      }
    }
    result[:note][:stats] = note.stats if note.stats.present?
    result[:actions_count] = note.actions.length if note.actions.present?
    result
  end

  def roll_dice_tool(arguments)
    RollService.roll(arguments)
  rescue RollService::InvalidDiceNotation, RollService::InvalidDiceParameters => e
    { success: false, error: e.message }
  end

  def call_note_action_tool(arguments)
    note = game.game_notes.find_by(id: arguments["note_id"])

    unless note
      return {
        success: false,
        error: "Note with ID #{arguments['note_id']} not found"
      }
    end

    unless note.actions.present?
      return {
        success: false,
        error: "Note has no actions defined"
      }
    end

    action_index = arguments["action_index"]
    result = note.call_action(action_index)

    # Reload note to get updated history
    note.reload

    if result[:success]
      {
        success: true,
        message: "Action executed successfully",
        note_id: note.id,
        action_result: result,
        history_count: note.history&.length || 0
      }
    else
      result
    end
  end

  def set_note_stats_tool(arguments)
    note = game.game_notes.find_by(id: arguments["note_id"])

    unless note
      return {
        success: false,
        error: "Note with ID #{arguments['note_id']} not found"
      }
    end

    unless arguments["stats"].is_a?(Hash)
      return {
        success: false,
        error: "Stats must be an object/hash of key-value pairs"
      }
    end

    note.update!(stats: arguments["stats"])

    {
      success: true,
      message: "Stats set successfully",
      note_id: note.id,
      stats: note.stats
    }
  end

  def update_note_stats_tool(arguments)
    note = game.game_notes.find_by(id: arguments["note_id"])

    unless note
      return {
        success: false,
        error: "Note with ID #{arguments['note_id']} not found"
      }
    end

    unless arguments["stats"].is_a?(Hash)
      return {
        success: false,
        error: "Stats must be an object/hash of key-value pairs"
      }
    end

    # Merge new stats with existing stats
    current_stats = note.stats || {}
    updated_stats = current_stats.merge(arguments["stats"])

    note.update!(stats: updated_stats)

    {
      success: true,
      message: "Stats updated successfully",
      note_id: note.id,
      stats: note.stats
    }
  end

  def delete_game_note_tool(arguments)
    note = game.game_notes.find_by(id: arguments["note_id"])

    unless note
      return {
        success: false,
        error: "Note with ID #{arguments['note_id']} not found"
      }
    end

    note.destroy!

    {
      success: true,
      message: "Note deleted successfully",
      note_id: arguments["note_id"]
    }
  end

  def update_plan_tool(arguments)
    unless arguments["items"].is_a?(Array)
      return {
        success: false,
        error: "Items must be an array"
      }
    end

    # Normalize items to ensure they have both description and completed fields
    plan_items = arguments["items"].map do |item|
      {
        "description" => item["description"],
        "completed" => item["completed"] || false
      }
    end

    self.plan = plan_items
    save!

    {
      success: true,
      message: "Plan updated successfully",
      plan: self.plan,
      count: self.plan.length
    }
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
