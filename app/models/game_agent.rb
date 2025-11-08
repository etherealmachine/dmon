# == Schema Information
#
# Table name: game_agents
#
#  id                   :bigint           not null, primary key
#  conversation_history :json
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

  def model
    "gpt-5-nano"
  end

  def call(input)
    raise "OpenAI API key not configured" unless openai_client

    # Store input for slash commands to access
    @current_input = input

    # Check for slash commands
    if input.strip.match?(/^\/(\w+)/)
      command_name = input.strip.match(/^\/(\w+)/)[1]
      command_method = "#{command_name}_command"

      if respond_to?(command_method, true)
        result = send(command_method)
        if result
          add_message(role: "assistant", content: result.to_json)
        end
        return result
      end
      # If command doesn't exist, fall through to normal processing
    end

    transaction do
      add_message(role: "user", content: input)

      # Make initial API call with tools
      response = openai_client.chat(
        parameters: {
          model:,
          messages: conversation_messages,
          tools: tool_definitions,
          tool_choice: "auto"
        })

      message = response.dig("choices", 0, "message")

      # Handle tool calls if present
      if message["tool_calls"]
        # Add assistant message with tool calls to history
        add_message(
          role: "assistant",
          content: message["content"] || "",
          tool_calls: message["tool_calls"]
        )

        # Execute each tool call
        message["tool_calls"].each do |tool_call|
          tool_result = execute_tool(
            tool_call["function"]["name"],
            JSON.parse(tool_call["function"]["arguments"])
          )

          # Add tool result to conversation history
          add_message(
            role: "tool",
            content: tool_result.to_json,
            tool_call_id: tool_call["id"]
          )
        end

        # Make another API call to get final response
        final_response = openai_client.chat(
          parameters: {
            model:,
            messages: conversation_messages,
            tools: tool_definitions,
            tool_choice: "auto"
          })

        content = final_response.dig("choices", 0, "message", "content") || ""
        add_message(role: "assistant", content: content)
      else
        # No tool calls, just add the response
        content = message["content"] || ""
        add_message(role: "assistant", content: content)
      end
    rescue Faraday::BadRequestError => e
      if e.response[:body].dig("error", "message")
        raise Error.new("OpenAI API request failed: #{e.response[:body]["error"]["message"]}")
      else
        raise Error.new("OpenAI API request failed: #{e.response[:body]}")
      end
    end
  end

  def clear!
    self.conversation_history = []
    save!
  end

  def tool_definitions
    [
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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
        }
      },
      {
        type: "function",
        function: {
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

  def openai_client
    @client ||= OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end

  def ensure_conversation_history
    self.conversation_history ||= []
  end

  def conversation_messages
    [
      { role: "system", content: system_prompt }
    ] + context_messages + conversation_history
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

  def context_messages
    game.game_notes.where(note_type: "context").map do |note|
      {
        role: "system", content: {
          type: "note",
          note_id: note.id,
          content: note.content
        }.to_json
      }
    end
  end

  def system_prompt
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
end
