import React, { useEffect, useState } from 'react';
import Conversation from './Conversation';
import ChatInput from './ChatInput';

interface PlanItem {
  description: string;
  completed: boolean;
}

interface ConversationMessage {
  role: string;
  content: string;
  tool_calls?: Array<{
    id: string;
    type: string;
    function: {
      name: string;
      arguments: string;
    };
  }>;
  tool_call_id?: string;
}

interface SidebarProps {
  gameId: number;
  plan: PlanItem[];
  model: string;
  conversationHistory: ConversationMessage[];
  selectedNoteGlobalIds?: string[];
}

const Sidebar: React.FC<SidebarProps> = ({ gameId, plan: initialPlan, model, conversationHistory: initialHistory, selectedNoteGlobalIds = [] }) => {
  const [conversationHistory, setConversationHistory] = useState<ConversationMessage[]>(initialHistory);
  const [plan, setPlan] = useState<PlanItem[]>(initialPlan);
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    // Subscribe to the agent channel
    if (typeof window !== 'undefined' && (window as any).AgentChannel) {
      const agentChannel = (window as any).AgentChannel;
      agentChannel.subscribe(gameId);

      // Set up message handlers
      (window as any).AgentUI = {
        handleUserMessage: (data: any) => {
          console.log('User message:', data.content);
        },

        handleAssistantStart: (data: any) => {
          // Add a new empty assistant message that we'll stream into
          setConversationHistory(prev => [...prev, {
            role: 'assistant',
            content: ''
          }]);
        },

        handleContent: (data: any) => {
          // Append to the last assistant message
          setConversationHistory(prev => {
            const newHistory = [...prev];
            const lastMessage = newHistory[newHistory.length - 1];
            if (lastMessage && lastMessage.role === 'assistant') {
              lastMessage.content += data.content;
            }
            return newHistory;
          });
        },

        handleToolCallsStart: (data: any) => {
          console.log(`Executing ${data.count} tool call(s)...`);
        },

        handleToolCall: (data: any) => {
          console.log('Tool call:', data.name);
        },

        handleToolResult: (data: any) => {
          console.log('Tool result:', data.name);
        },

        handleToolCallsComplete: (data: any) => {
          console.log('Tools executed successfully');
        },

        handleJobComplete: (data: any) => {
          console.log('Job complete, reloading page...');
          setIsProcessing(false);
          window.location.reload();
        },

        handleError: (data: any) => {
          console.error('Agent error:', data.error);
          if (data.backtrace) {
            console.error('Backtrace:', data.backtrace);
          }
          setIsProcessing(false);

          // Format error with backtrace if available
          let errorContent = data.error;
          if (data.backtrace && Array.isArray(data.backtrace)) {
            errorContent += '\n\n**Stack trace:**\n```\n' + data.backtrace.join('\n') + '\n```';
          }

          setConversationHistory(prev => [...prev, {
            role: 'error',
            content: errorContent
          }]);
        }
      };
    }

    // Cleanup on unmount
    return () => {
      if (typeof window !== 'undefined' && (window as any).AgentChannel) {
        (window as any).AgentChannel.unsubscribe();
      }
    };
  }, [gameId]);

  const handleSubmit = async (input: string, contextItems: string[], selectedModel: string) => {
    if (isProcessing) {
      alert('Please wait for the current request to complete');
      return;
    }

    setIsProcessing(true);

    // Add user message to conversation immediately
    setConversationHistory(prev => [...prev, {
      role: 'user',
      content: input
    }]);

    const formData = new FormData();
    formData.append('input', input);
    formData.append('model', selectedModel);
    contextItems.forEach(item => {
      formData.append('context_items[]', item);
    });

    try {
      const response = await fetch(`/games/${gameId}/agent`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
          'Accept': 'application/json'
        }
      });

      const data = await response.json();
      console.log('Request submitted:', data);
    } catch (error) {
      console.error('Error:', error);
      setIsProcessing(false);
      setConversationHistory(prev => [...prev, {
        role: 'error',
        content: error instanceof Error ? error.message : 'Unknown error'
      }]);
    }
  };

  return (
    <div className="w-96 bg-white border-l border-gray-200 flex flex-col h-[calc(100vh-4rem)]">
      {/* Scrollable conversation area */}
      <div className="flex-1 overflow-y-auto">
        <Conversation conversationHistory={conversationHistory} />
      </div>

      {/* Plan section - fixed at bottom above input */}
      {plan && plan.length > 0 && (
        <div className="border-t border-gray-200 p-4 flex-shrink-0">
          <h4 className="text-sm font-semibold text-gray-700 mb-3">Current Plan</h4>
          <div className="space-y-2">
            {plan.map((item, index) => (
              <div key={index} className="flex items-start gap-2 text-sm">
                <div className="flex-shrink-0 mt-0.5">
                  {item.completed ? (
                    <svg className="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                  ) : (
                    <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                  )}
                </div>
                <span className={item.completed ? 'text-gray-500 line-through' : 'text-gray-700'}>
                  {item.description}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Chat input - fixed at bottom */}
      <ChatInput
        gameId={gameId}
        model={model}
        onSubmit={handleSubmit}
        isProcessing={isProcessing}
        selectedNoteGlobalIds={selectedNoteGlobalIds}
      />
    </div>
  );
};

export default Sidebar;
