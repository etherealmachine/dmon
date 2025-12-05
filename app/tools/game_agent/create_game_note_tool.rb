module GameAgentTools
  class CreateGameNoteTool < RubyLLM::Tool
    description "Create a new note for this game. Use this to save important information, reminders, or observations that should be persisted. Optionally attach actions (like dice rolls) that can be executed later, or set initial stats."

    def name
      "create_game_note"
    end

    params({
      "type" => "object",
      "properties" => {
        "content" => {
          "type" => "string",
          "description" => "The note contents - markdown is supported"
        },
        "note_type" => {
          "type" => "string",
          "enum" => GameNote.note_types.map(&:second),
          "description" => "The type of note"
        },
        "title" => {
          "type" => "string",
          "description" => "Optional title for the note (e.g., 'Human Bandit', 'Magic Sword +1', 'Town of Oakvale')"
        },
        "stats" => {
          "type" => "object",
          "description" => "Optional object containing stat key-value pairs (e.g., {\"HP\": 45, \"AC\": 18})",
          "additionalProperties" => true
        },
        "actions" => {
          "type" => "array",
          "description" => "Optional array of actions that can be executed later (e.g., dice rolls for attacks or abilities)"
        }
      },
      "required" => ["content", "note_type"],
      "additionalProperties" => false
    })

    def initialize(game)
      @game = game
    end

    def execute(content:, note_type:, title: nil, stats: nil, actions: nil)
      note_params = { content: content, note_type: note_type }
      note_params[:title] = title if title.present?
      note_params[:stats] = stats if stats.present?
      note_params[:actions] = actions if actions.present?

      note = @game.game_notes.create!(note_params)

      result = { success: true, note_id: note.id, message: "Note created successfully" }
      result[:title] = note.title if note.title.present?
      result[:stats] = note.stats if note.stats.present?
      result[:actions_count] = note.actions.length if note.actions.present?
      result
    rescue => e
      { success: false, error: e.message }
    end
  end
end
