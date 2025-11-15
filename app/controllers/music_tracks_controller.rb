class MusicTracksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_music_track, only: [:show, :destroy]

  def create
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    # Handle both single file (music_track) and multiple files (music_tracks[])
    files = params[:music_tracks] || [params[:music_track]].compact

    if files.present?
      files.each do |file|
        @game.music_tracks.attach(file)
      end

      count = files.is_a?(Array) ? files.length : 1
      message = count > 1 ? "#{count} music tracks uploaded successfully." : "Music track uploaded successfully."
      redirect_to game_path(@game), notice: message
    else
      redirect_to game_path(@game), alert: "No file provided."
    end
  end

  def show
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    # The music track will be rendered in a view
  end

  def destroy
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    @music_track.purge
    redirect_to game_path(@game), notice: "Music track deleted successfully."
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_music_track
    @music_track = @game.music_tracks.find(params[:id])
  end
end
