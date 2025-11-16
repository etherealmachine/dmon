class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    @games = current_user.games.order(updated_at: :desc)
  end
end
