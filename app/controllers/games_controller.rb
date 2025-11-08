class GamesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game, only: [:show, :agent]

  def index
    @games = current_user.games.order(created_at: :desc)
  end

  def new
    @game = Game.new
  end

  def create
    @game = current_user.games.build

    if @game.save
      # Attach PDF if provided
      if params[:game][:pdf].present?
        pdf = @game.pdfs.build
        pdf.name = params[:game][:pdf].original_filename
        pdf.description = "Processing..."
        pdf.pdf.attach(params[:game][:pdf])
        pdf.save
        @game.pdfs << pdf
        @game.save
      end

      redirect_to @game, notice: 'Game was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @game_notes = @game.game_notes.chronological
  end

  def agent
    if request.post?
      @game.agent.call(params[:input])
      redirect_to @game
    else
    end
  end

  private

  def set_game
    @game = Game.find(params[:id])
  end
end
