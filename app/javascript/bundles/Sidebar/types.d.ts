interface AgentUI {
  currentMessageElement: HTMLElement | null;
  conversationContainer: HTMLElement | null;
  isProcessing: boolean;
  init(): void;
  handleFormSubmit(e: Event): void;
  handleUserMessage(data: any): void;
  handleAssistantStart(data: any): void;
  handleContent(data: any): void;
  handleToolCallsStart(data: any): void;
  handleToolCall(data: any): void;
  handleToolResult(data: any): void;
  handleToolCallsComplete(data: any): void;
  handleJobComplete(data: any): void;
  handleError(data: { error: string }): void;
  scrollToBottom(): void;
  escapeHtml(text: string): string;
  disableForm(form: HTMLFormElement): void;
  enableForm(form: HTMLFormElement): void;
}

interface AgentChannel {
  subscribe(gameId: number): void;
}

interface Window {
  AgentUI?: AgentUI;
  AgentChannel?: AgentChannel;
}
