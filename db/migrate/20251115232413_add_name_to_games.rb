class AddNameToGames < ActiveRecord::Migration[8.0]
  def change
    add_column :games, :name, :string
  end
end
