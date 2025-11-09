import consumer from "./consumer"

// This will be initialized when the page loads if we're on a game show page
window.AgentChannel = {
  subscription: null,

  subscribe(gameId) {
    if (this.subscription) {
      return this.subscription
    }

    this.subscription = consumer.subscriptions.create(
      { channel: "AgentChannel", game_id: gameId },
      {
        connected() {
          console.log("Connected to AgentChannel")
        },

        disconnected() {
          console.log("Disconnected from AgentChannel")
        },

        received(data) {
          // Handle different message types
          switch(data.type) {
            case "user_message":
              window.AgentUI?.handleUserMessage(data)
              break
            case "assistant_start":
              window.AgentUI?.handleAssistantStart(data)
              break
            case "content":
              window.AgentUI?.handleContent(data)
              break
            case "tool_calls_start":
              window.AgentUI?.handleToolCallsStart(data)
              break
            case "tool_call":
              window.AgentUI?.handleToolCall(data)
              break
            case "tool_result":
              window.AgentUI?.handleToolResult(data)
              break
            case "tool_calls_complete":
              window.AgentUI?.handleToolCallsComplete(data)
              break
            case "job_complete":
              window.AgentUI?.handleJobComplete(data)
              break
            case "error":
              window.AgentUI?.handleError(data)
              break
            default:
              console.log("Unknown message type:", data.type, data)
          }
        }
      }
    )

    return this.subscription
  },

  unsubscribe() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }
}
