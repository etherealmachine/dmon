class GameNotesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_game_note, only: [:update, :destroy, :call_action, :clear_history, :update_stat, :delete_stat, :delete_action, :delete_history_item, :attach_image, :detach_image]

  def create
    @game_note = @game.game_notes.build(game_note_params)

    respond_to do |format|
      if @game_note.save
        format.html { redirect_to @game, notice: 'Note was successfully created.' }
        format.json { render json: { success: true, note: note_json(@game_note) }, status: :created }
      else
        format.html { redirect_to @game, alert: "Unable to create note: #{@game_note.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @game_note.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @game_note.update(game_note_params)
        format.html { redirect_to @game, notice: 'Note was successfully updated.' }
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.html { redirect_to @game, alert: "Unable to update note: #{@game_note.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @game_note.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @game_note.destroy
    redirect_to @game, notice: 'Note was successfully deleted.'
  end

  def call_action
    action_index = params[:action_index].to_i
    result = @game_note.call_action(action_index)

    respond_to do |format|
      if result[:success]
        format.html { redirect_to @game, notice: "Action executed successfully." }
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.html { redirect_to @game, alert: "Action failed: #{result[:error]}" }
        format.json { render json: { success: false, error: result[:error] }, status: :unprocessable_entity }
      end
    end
  end

  def clear_history
    respond_to do |format|
      if @game_note.clear_history
        format.html { redirect_to @game, notice: "History cleared successfully." }
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.html { redirect_to @game, alert: "Failed to clear history." }
        format.json { render json: { success: false, error: "Failed to clear history" }, status: :unprocessable_entity }
      end
    end
  end

  def update_stat
    stat_key = params[:stat_key]
    stat_value = params[:stat_value]

    respond_to do |format|
      if @game_note.update_stat(stat_key, stat_value)
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.json { render json: { success: false, error: "Failed to update stat" }, status: :unprocessable_entity }
      end
    end
  end

  def delete_stat
    stat_key = params[:stat_key]

    respond_to do |format|
      if @game_note.delete_stat(stat_key)
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.json { render json: { success: false, error: "Failed to delete stat" }, status: :unprocessable_entity }
      end
    end
  end

  def delete_action
    action_index = params[:action_index].to_i

    respond_to do |format|
      if @game_note.delete_action(action_index)
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.json { render json: { success: false, error: "Failed to delete action" }, status: :unprocessable_entity }
      end
    end
  end

  def delete_history_item
    history_index = params[:history_index].to_i

    respond_to do |format|
      if @game_note.delete_history_item(history_index)
        format.json { render json: { success: true, note: note_json(@game_note) } }
      else
        format.json { render json: { success: false, error: "Failed to delete history item" }, status: :unprocessable_entity }
      end
    end
  end

  def attach_image
    pdf_id = params[:pdf_id]
    image_index = params[:image_index].to_i

    pdf = @game.pdfs.find_by(id: pdf_id)

    respond_to do |format|
      if pdf.nil?
        format.json { render json: { success: false, error: "PDF not found" }, status: :not_found }
      elsif image_index < 0 || image_index >= pdf.images.count
        format.json { render json: { success: false, error: "Invalid image index" }, status: :unprocessable_entity }
      else
        # Attach the blob from the PDF's image to this note
        @game_note.images.attach(pdf.images[image_index].blob)
        format.json { render json: { success: true, note: note_json(@game_note) } }
      end
    end
  end

  def detach_image
    image_index = params[:image_index].to_i

    respond_to do |format|
      if image_index < 0 || image_index >= @game_note.images.count
        format.json { render json: { success: false, error: "Invalid image index" }, status: :unprocessable_entity }
      else
        @game_note.images[image_index].purge
        format.json { render json: { success: true, note: note_json(@game_note) } }
      end
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
    params.require(:game_note).permit(:title, :note_type, :content)
  end

  def note_json(note)
    {
      id: note.id,
      global_id: note.to_global_id.to_s,
      title: note.title,
      note_type: note.note_type,
      content: note.content,
      created_at: note.created_at.iso8601,
      stats: note.stats,
      actions: note.actions,
      history: note.history,
      images: note.images.attached? ? note.images.map { |img| rails_blob_path(img) } : []
    }
  end
end
