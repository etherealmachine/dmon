module GameAgentTools
  class UpdateNoteStatsTool < RubyLLM::Tool
    description "Update specific stats on a game note without replacing all stats. Only the provided stat keys will be updated or added, existing stats not mentioned will remain unchanged."

    def name
      "update_note_stats"
    end

    params do
      integer :note_id, description: "The ID of the note to update", required: true

    def name
      "update_note_stats"
    end
      object :stats, description: "Object containing stat key-value pairs to update (e.g., {\"HP\": 30}). Values can be numbers or strings.", required: true

    def name
      "update_note_stats"
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

      # Merge new stats with existing stats
      current_stats = note.stats || {}
      updated_stats = current_stats.merge(stats)

      note.update!(stats: updated_stats)

      {
        success: true,
        message: "Stats updated successfully",
        note_id: note.id,
        stats: note.stats
      }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
