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

    respond_to do |format|
      format.html
      format.json { render json: @game }
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

  private

  def set_game
    @game = Game.find(params[:id])
  end
end
