module GameAgentTools
  class EditGameNoteTool < RubyLLM::Tool
    description "Edit an existing game note by its ID. Can update the title, content, or note type. Use set_note_stats or update_note_stats to modify stats."

    def name
      "edit_game_note"
    end

    params do
      integer :note_id, description: "The ID of the note to edit", required: true
      string :title, description: "Updated title for the note (optional)", required: false
      string :content, description: "Updated note content (markdown supported, optional)", required: false
      string :note_type, enum: GameNote.note_types.map(&:second),
             description: "Updated note type (optional)", required: false
    end

    def initialize(game)
      @game = game
    end

    def execute(note_id:, title: nil, content: nil, note_type: nil)
      note = @game.game_notes.find_by(id: note_id)

      unless note
        return {
          success: false,
          error: "Note with ID #{note_id} not found"
        }
      end

      # Update only the fields that are provided
      update_params = {}
      update_params[:title] = title unless title.nil?
      update_params[:content] = content if content.present?
      update_params[:note_type] = note_type if note_type.present?

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
          title: note.title,
          content: note.content,
          note_type: note.note_type,
          created_at: note.created_at,
          updated_at: note.updated_at
        }
      }
      result[:note][:stats] = note.stats if note.stats.present?
      result[:actions_count] = note.actions.length if note.actions.present?
      result
    rescue => e
      { success: false, error: e.message }
    end
  end
end
