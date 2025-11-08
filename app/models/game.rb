# == Schema Information
#
# Table name: games
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_games_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Game < ApplicationRecord
  belongs_to :user
  has_many :pdfs, dependent: :destroy
  has_many :game_notes, dependent: :destroy
  has_one :game_agent, dependent: :destroy

  validates :user, presence: true

  def agent
    game_agent || build_game_agent
  end
end
