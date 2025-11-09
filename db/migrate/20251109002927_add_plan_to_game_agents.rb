class AddPlanToGameAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :game_agents, :plan, :json
  end
end
