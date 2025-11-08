# == Schema Information
#
# Table name: game_notes
#
#  id         :bigint           not null, primary key
#  actions    :jsonb
#  content    :text
#  history    :jsonb
#  note_type  :string
#  stats      :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  game_id    :bigint           not null
#
# Indexes
#
#  index_game_notes_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
require "test_helper"

class GameNoteTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
