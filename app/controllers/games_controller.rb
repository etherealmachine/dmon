class GamesController < ApplicationController
  before_action :authenticate_user!, except: [:index]
  before_action :set_game, only: [:show, :update, :agent, :available_images, :download]

  def index
    # Get example games
    example_user = User.find_by(provider: "example", uid: "example_user")
    @example_games = example_user&.games&.order(created_at: :desc) || []
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

  def create_from_upload
    unless user_signed_in?
      redirect_to login_path, alert: 'Please sign in to upload PDFs.'
      return
    end

    unless params[:pdf_file].present?
      redirect_to root_path, alert: 'Please select a PDF file.'
      return
    end

    # Extract filename without extension for game name
    filename = params[:pdf_file].original_filename
    game_name = filename.gsub(/\.pdf$/i, '')

    # Create game with PDF name
    @game = current_user.games.build(name: game_name)

    if @game.save
      # Create and attach PDF
      pdf = @game.pdfs.build(name: game_name)
      pdf.pdf.attach(params[:pdf_file])

      if pdf.save
        redirect_to @game, notice: 'Game created! Processing your PDF...'
      else
        @game.destroy
        redirect_to root_path, alert: "Failed to upload PDF: #{pdf.errors.full_messages.join(', ')}"
      end
    else
      redirect_to root_path, alert: "Failed to create game: #{@game.errors.full_messages.join(', ')}"
    end
  end

  def show
    @game_notes = @game.game_notes.chronological

    respond_to do |format|
      format.html
      format.json { render json: @game }
    end
  end

  def update
    if @game.update(game_params)
      respond_to do |format|
        format.json { render json: { success: true, name: @game.name } }
        format.html { redirect_to @game, notice: 'Game was successfully updated.' }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: @game.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to @game, alert: 'Failed to update game.' }
      end
    end
  end

  def agent
    if request.post?
      # Get selected context items from params (GlobalIDs)
      context_items = params[:context_items] || []

      if params[:model].present?
        @game.user.preferred_model = params[:model]
      end

      # Queue the agent job for async processing
      AgentCallJob.perform_later(
        @game.id,
        params[:input],
        context_items: context_items)

      # Return success response for AJAX requests
      if request.xhr?
        render json: { success: true, message: "Processing your request..." }
      else
        # Redirect back with context items to preserve checkbox state
        redirect_to @game, context_items: context_items, notice: "Processing your request..."
      end
    else
      # Provide debug information for the view
      agent = @game.agent
      @context_string = agent.send(:context_string)
      @context_messages = agent.send(:context_messages)
      @conversation_history = agent.conversation_history || []
      @tool_definitions = agent.unified_tool_definitions
    end
  end

  def available_images
    # Get all PDFs for this game with their images
    pdfs_with_images = @game.pdfs.map do |pdf|
      next unless pdf.images.attached?

      {
        id: pdf.id,
        name: pdf.name,
        images: pdf.images.map.with_index do |image, index|
          {
            pdf_id: pdf.id,
            image_index: index,
            url: rails_blob_path(image)
          }
        end
      }
    end.compact

    render json: { pdfs: pdfs_with_images }
  end

  def download
    # Create the export (returns zip file contents)
    zip_data = GameExport.new(@game).call

    # Send the data to the user
    game_name = @game.name.presence || "game_#{@game.id}"
    send_data(
      zip_data,
      filename: "#{game_name}.zip",
      type: 'application/zip',
      disposition: 'attachment'
    )
  end

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def game_params
    params.require(:game).permit(:name)
  end
end
