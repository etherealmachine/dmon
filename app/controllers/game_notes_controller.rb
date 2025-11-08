class GameNotesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_game_note, only: [:update, :destroy, :call_action]

  def create
    @game_note = @game.game_notes.build(game_note_params)

    if @game_note.save
      redirect_to @game, notice: 'Note was successfully created.'
    else
      redirect_to @game, alert: "Unable to create note: #{@game_note.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @game_note.update(game_note_params)
      redirect_to @game, notice: 'Note was successfully updated.'
    else
      redirect_to @game, alert: "Unable to update note: #{@game_note.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @game_note.destroy
    redirect_to @game, notice: 'Note was successfully deleted.'
  end

  def call_action
    action_index = params[:action_index].to_i
    result = @game_note.call_action(action_index)

    if result[:success]
      redirect_to @game, notice: "Action executed successfully."
    else
      redirect_to @game, alert: "Action failed: #{result[:error]}"
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_game_note
    @game_note = @game.game_notes.find(params[:id])
  end

  def game_note_params
    params.require(:game_note).permit(:note_type, :content)
  end
end
