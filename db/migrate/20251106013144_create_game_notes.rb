class CreateGameNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :game_notes do |t|
      t.references :game, null: false, foreign_key: true
      t.text :content
      t.string :note_type
      t.jsonb :stats
      t.jsonb :actions
      t.jsonb :history

      t.timestamps
    end
  end
end
