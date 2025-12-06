module GameAgentTools
  class DeleteGameNoteTool < RubyLLM::Tool
    description "Delete a game note by its ID. This permanently removes the note and cannot be undone."

    def name
      "delete_game_note"
    end

    params do
      integer :note_id, description: "The ID of the note to delete", required: true
    end

    def initialize(game)
      @game = game
    end

    def execute(note_id:)
      note = @game.game_notes.find_by(id: note_id)

      unless note
        return {
          success: false,
          error: "Note with ID #{note_id} not found"
        }
      end

      note.destroy!

      {
        success: true,
        message: "Note deleted successfully",
        note_id: note_id
      }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
