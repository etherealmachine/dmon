module GameAgentTools
  class SearchGameNotesTool < RubyLLM::Tool
    description "Search for game notes by keyword or filter by note type. Returns a list of matching notes with their IDs, content, and metadata."

    def name
      "search_game_notes"
    end

    params do
      string :query, description: "Optional search query to filter notes by content", required: false
      string :note_type, enum: GameNote.note_types.map(&:second),
             description: "Optional filter by note type", required: false
    end

    def initialize(game)
      @game = game
    end

    def execute(query: nil, note_type: nil)
      notes = @game.game_notes

      # Filter by note type if provided
      notes = notes.where(note_type: note_type) if note_type.present?

      # Filter by query if provided (search in content)
      if query.present?
        notes = notes.where("content ILIKE ?", "%#{query}%")
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
    rescue => e
      { success: false, error: e.message }
    end
  end
end
