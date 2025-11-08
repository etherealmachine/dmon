class CreateGameAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :game_agents do |t|
      t.references :game, null: false, foreign_key: true
      t.json :conversation_history

      t.timestamps
    end
  end
end
