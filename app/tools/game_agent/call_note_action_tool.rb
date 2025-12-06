module GameAgentTools
  class CallNoteActionTool < RubyLLM::Tool
    description "Execute an action attached to a game note. Actions are pre-defined operations (like dice rolls) that can be triggered. The result is added to the note's action history."

    def name
      "call_note_action"
    end

    params do
      integer :note_id, description: "The ID of the note containing the action", required: true
      integer :action_index, description: "The index of the action to execute (0-based, so first action is 0, second is 1, etc.)", required: true
    end

    def initialize(game)
      @game = game
    end

    def execute(note_id:, action_index:)
      note = @game.game_notes.find_by(id: note_id)

      unless note
        return {
          success: false,
          error: "Note with ID #{note_id} not found"
        }
      end

      unless note.actions.present?
        return {
          success: false,
          error: "Note has no actions defined"
        }
      end

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
    rescue => e
      { success: false, error: e.message }
    end
  end
end
