module GameAgentTools
  class SetNoteStatsTool < RubyLLM::Tool
    description "Set or update stats (key-value pairs) on a game note. Stats are useful for tracking numeric values like HP, AC, ability scores, or any other game-relevant data. This replaces all existing stats on the note."

    def name
      "set_note_stats"
    end

    params do
      integer :note_id, description: "The ID of the note to update", required: true
      object :stats, description: "Object containing stat key-value pairs (e.g., {\"HP\": 45, \"AC\": 18, \"STR\": 16}). Values can be numbers or strings.", required: true do
        # Free-form object - accepts any stat key-value pairs
      end
    end

    def initialize(game)
      @game = game
    end

    def execute(note_id:, stats:)
      note = @game.game_notes.find_by(id: note_id)

      unless note
        return {
          success: false,
          error: "Note with ID #{note_id} not found"
        }
      end

      unless stats.is_a?(Hash)
        return {
          success: false,
          error: "Stats must be an object/hash of key-value pairs"
        }
      end

      note.update!(stats: stats)

      {
        success: true,
        message: "Stats set successfully",
        note_id: note.id,
        stats: note.stats
      }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
