class AgentCallJob < ApplicationJob
  queue_as :default

  def perform(game_id, input, context_items: [])
    game = Game.find(game_id)
    agent = game.agent

    # Call the agent with streaming enabled (by passing a block)
    agent.call(input, context_items: context_items) do |chunk|
      # Broadcast each chunk to the client via ActionCable
      AgentChannel.broadcast_to(game, chunk)
    end

    # Broadcast completion
    AgentChannel.broadcast_to(game, {
      type: "job_complete",
      conversation_history: agent.conversation_history,
      plan: agent.plan
    })
  rescue StandardError => e
    # Broadcast error to client with full debugging information
    error_data = {
      type: "error",
      error: "#{e.class}: #{e.message}"
    }

    # Always include backtrace in development, optionally in production
    if Rails.env.development? || Rails.env.test?
      error_data[:backtrace] = e.backtrace.first(20)
    end

    AgentChannel.broadcast_to(Game.find(game_id), error_data)
    raise e
  end
end
