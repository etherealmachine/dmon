class PdfsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_game
  before_action :set_pdf, except: [:create]

  def create
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    @pdf = @game.pdfs.build(pdf_params)

    # Set name from filename if not provided
    if @pdf.name.blank? && params.dig(:pdf, :pdf).present?
      @pdf.name = params[:pdf][:pdf].original_filename.gsub('.pdf', '')
    end

    if @pdf.save
      redirect_to game_path(@game), notice: "PDF uploaded successfully. Processing has been queued."
    else
      redirect_to game_path(@game), alert: "Failed to upload PDF: #{@pdf.errors.full_messages.join(', ')}"
    end
  end

  def show
    # Ensure the user owns the game
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end
  end

  def reparse
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    ParsePdfJob.perform_later(@pdf.id, process_metadata: true)
    redirect_to game_pdf_path(@game, @pdf), notice: "PDF reparse has been queued. This may take a few moments."
  end

  def reclassify_images
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    ClassifyImagesJob.perform_later(@pdf.id, reclassify: true)
    redirect_to game_pdf_path(@game, @pdf), notice: "Image reclassification has been queued. This may take a few moments."
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_pdf
    @pdf = @game.pdfs.find(params[:id])
  end

  def pdf_params
    params.require(:pdf).permit(:pdf, :name, :description)
  end
end
