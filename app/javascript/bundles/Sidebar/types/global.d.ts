export {};

declare global {
  interface Window {
    AgentChannel: {
      subscribe: (gameId: number) => any;
      unsubscribe: () => void;
      subscription: any;
    };
    AgentUI: {
      handleUserMessage: (data: any) => void;
      handleAssistantStart: (data: any) => void;
      handleContent: (data: any) => void;
      handleToolCallsStart: (data: any) => void;
      handleToolCall: (data: any) => void;
      handleToolResult: (data: any) => void;
      handleToolCallsComplete: (data: any) => void;
      handleJobComplete: (data: any) => void;
      handleError: (data: any) => void;
    };
  }
}
