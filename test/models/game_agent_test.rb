# == Schema Information
#
# Table name: game_agents
#
#  id                   :bigint           not null, primary key
#  conversation_history :json
#  plan                 :json
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  game_id              :bigint           not null
#
# Indexes
#
#  index_game_agents_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
require "test_helper"

class GameAgentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
