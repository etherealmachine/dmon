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
    # Broadcast error to client
    AgentChannel.broadcast_to(Game.find(game_id), {
      type: "error",
      error: e.message,
      backtrace: Rails.env.development? ? e.backtrace.first(10) : nil
    })
    raise e
  end
end
