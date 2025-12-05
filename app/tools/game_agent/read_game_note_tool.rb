module GameAgentTools
  class ReadGameNoteTool < RubyLLM::Tool
    description "Read the full details of a specific game note by its ID. Returns the complete note content including input, output, type, and timestamps."

    def name
      "read_game_note"
    end

    params do
      integer :note_id, description: "The ID of the note to read", required: true

    def name
      "read_game_note"
    end
    end

    def initialize(game)
      @game = game
    end

    def execute(note_id:)
      note = @game.game_notes.find_by(id: note_id)

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
          error: "Note with ID #{note_id} not found"
        }
      end
    rescue => e
      { success: false, error: e.message }
    end
  end
end
