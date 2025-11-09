class AgentChannel < ApplicationCable::Channel
  def subscribed
    game = Game.find(params[:game_id])
    # Verify user has access to this game
    reject unless game.user_id == current_user.id

    stream_for game
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
