# Async/Streaming Agent Implementation

This document describes the async/streaming implementation for the GameAgent AI interactions.

## Overview

The synchronous `agent.call()` method has been converted to use:
- **ActionCable WebSockets** for real-time streaming
- **ActiveJob background processing** for async execution
- **Server-Sent Events (SSE)** via AI service streaming APIs

## Architecture

### 1. Backend Components

#### ActionCable Channel (`app/channels/agent_channel.rb`)
- WebSocket channel for real-time communication
- Authenticated via Devise/Warden
- Broadcasts streaming chunks to connected clients

#### Background Job (`app/jobs/agent_call_job.rb`)
- Executes agent calls asynchronously
- Broadcasts progress updates via ActionCable
- Handles errors gracefully

#### AI Services (`app/services/`)
- **ClaudeService**: Added streaming support via Anthropic SDK
- **OpenAiService**: Added streaming support via OpenAI SDK
- Both services now accept `stream: true` parameter

#### GameAgent Model (`app/models/game_agent.rb`)
- Unified method: `call(input, context_items: [], &block)`
- Automatically streams if a block is provided
- Non-streaming mode when no block is given
- Yields chunks as they arrive from AI services
- Handles tool calls with streaming feedback

### 2. Frontend Components

#### ActionCable Consumer (`app/javascript/channels/`)
- `consumer.js`: Creates ActionCable connection
- `agent_channel.js`: Subscribes to agent updates for specific game
- Dispatches events to UI handler

#### UI Handler (`app/views/games/show.html.erb`)
- `window.AgentUI`: Manages streaming UI updates
- Handles different message types:
  - `assistant_start`: New message begins
  - `content`: Text chunks from AI
  - `tool_calls_start`: Tool execution begins
  - `tool_call`: Individual tool being called
  - `tool_result`: Tool execution result
  - `tool_calls_complete`: All tools complete
  - `job_complete`: Full request complete
  - `error`: Error handling

### 3. Controller Changes (`app/controllers/games_controller.rb`)
- POST to `/games/:id/agent` now queues a background job
- Returns immediately with success response
- Supports both AJAX and regular form submissions

## Message Flow

```
User submits message
    ↓
Controller queues AgentCallJob
    ↓
Job calls agent.call with block
    ↓
Agent detects block and streams to AI service
    ↓
AI service yields chunks
    ↓
Chunks broadcast via ActionCable
    ↓
JavaScript updates UI in real-time
    ↓
Job completes, page reloads to show final state
```

## Streaming Message Types

### User Messages
```javascript
{ type: "user_message", content: "..." }
```

### Assistant Streaming
```javascript
{ type: "assistant_start" }
{ type: "content", content: "partial text..." }
{ type: "content", content: "more text..." }
```

### Tool Calls
```javascript
{ type: "tool_calls_start", count: 2 }
{ type: "tool_call", name: "create_game_note", arguments: {...} }
{ type: "tool_result", name: "create_game_note", result: {...} }
{ type: "tool_calls_complete" }
```

### Completion
```javascript
{
  type: "job_complete",
  conversation_history: [...],
  plan: [...]
}
```

### Errors
```javascript
{ type: "error", error: "Error message", backtrace: [...] }
```

## Configuration

### ActionCable
- **Development**: Uses async adapter (in-memory)
- **Production**: Uses solid_cable (database-backed)
- Configuration: `config/cable.yml`

### Background Jobs
- Uses Rails default queue adapter (async in dev, sidekiq/solid_queue in prod)
- Job queue: `default`

## Testing

### Manual Testing
1. Start the Rails server: `bin/dev`
2. Navigate to a game page
3. Open browser console to see streaming events
4. Submit a message to the agent
5. Watch real-time updates in the conversation sidebar

### Console Testing
```ruby
# In rails console (must use web console for async adapter!)
game = Game.first
AgentCallJob.perform_now(game.id, "Tell me about this adventure", context_items: [])
```

## Benefits

1. **Non-blocking UI**: Users can see responses as they arrive
2. **Better UX**: Progressive disclosure of AI thinking process
3. **Error resilience**: Errors don't lock the UI
4. **Scalability**: Background jobs can be distributed
5. **Transparency**: Users see tool execution in real-time

## Usage Modes

The unified `agent.call()` method supports both modes:

### Streaming Mode (with block)
```ruby
agent.call(input, context_items: context_items) do |chunk|
  # Handle streaming chunks
  puts chunk
end
```

### Non-Streaming Mode (without block)
```ruby
result = agent.call(input, context_items: context_items)
# Blocks until complete, returns full result
```

This is useful for:
- Console usage
- Testing
- Direct API calls
- Slash commands

## Future Enhancements

1. **Markdown rendering**: Stream markdown as HTML
2. **Abort capability**: Allow users to cancel in-progress requests
3. **Multiple concurrent requests**: Queue and execute multiple requests
4. **Typing indicators**: Show when AI is "thinking"
5. **Retry logic**: Automatic retry on transient failures
6. **Progress indicators**: Show % complete for long operations
