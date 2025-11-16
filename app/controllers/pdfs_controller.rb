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

    # Get images and sort by classification and recommendation
    images = @pdf.images.filter { |image| image.blob.metadata['source'] == 'pdfimages' }

    # Define classification order (most valuable first)
    classification_order = {
      'map' => 1, 'character' => 2, 'monster' => 3, 'item' => 4,
      'scene' => 5, 'handout' => 6, 'table' => 7, 'decorative' => 8,
      'background' => 9, 'logo' => 10, 'artifact' => 11,
      'silhouette' => 12, 'incomplete' => 13, 'other' => 14
    }

    @images = images.sort_by do |image|
      classification = image.blob.metadata['classification'] || 'other'
      recommendation = image.blob.metadata['recommendation'] || 'keep'

      # Put "remove" recommendations at the end
      recommendation_order = recommendation == 'remove' ? 1000 : 0

      # Combine classification and recommendation for sorting
      [recommendation_order, classification_order[classification] || 999]
    end
  end

  def run_job
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    PdfJob.perform_later(@pdf.id, params[:method])
    redirect_to game_pdf_path(@game, @pdf), notice: "PDF job has been queued. This may take a few moments."
  end

  def html
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end
  end

  def image
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    @image = @pdf.images.find(params[:image_id])

    # Get all images with the same source as the current image for navigation
    all_images = @pdf.images.filter { |img| img.blob.metadata['source'] == 'pdfimages' }

    # Find the index of the current image
    @image_index = all_images.find_index { |img| img.id == @image.id }
    @total_images = all_images.count

    # Get previous and next images for navigation
    if @image_index && @image_index > 0
      @previous_image = all_images[@image_index - 1]
    end

    if @image_index && @image_index < @total_images - 1
      @next_image = all_images[@image_index + 1]
    end
  end

  def delete_images
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    image_ids = params[:image_ids] || []
    deleted_count = 0

    image_ids.each do |image_id|
      image = @pdf.images.find_by(id: image_id)
      if image
        image.purge
        deleted_count += 1
      end
    end

    redirect_to game_pdf_path(@game, @pdf), notice: "#{deleted_count} image(s) deleted successfully."
  end

  def upload_images
    unless @game.user == current_user
      redirect_to root_path, alert: "You don't have access to this game."
      return
    end

    uploaded_images = params[:images] || []
    uploaded_count = 0

    uploaded_images.each do |image_file|
      if image_file.present?
        @pdf.images.attach(
          io: image_file,
          filename: image_file.original_filename,
          content_type: image_file.content_type,
          metadata: { source: 'pdfimages' }
        )
        uploaded_count += 1
      end
    end

    if uploaded_count > 0
      redirect_to game_pdf_path(@game, @pdf), notice: "#{uploaded_count} image(s) uploaded successfully."
    else
      redirect_to game_pdf_path(@game, @pdf), alert: "No images were uploaded."
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def set_pdf
    @pdf = @game.pdfs.find(params[:id] || params[:pdf_id])
  end

  def pdf_params
    params.require(:pdf).permit(:pdf, :name, :description)
  end
end
