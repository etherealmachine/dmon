import React, { useEffect, useRef } from 'react';
import Message from './Message';

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

interface ConversationProps {
  conversationHistory: ConversationMessage[];
}

const Conversation: React.FC<ConversationProps> = ({ conversationHistory }) => {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Scroll to bottom when conversation updates
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [conversationHistory]);

  return (
    <div className="flex-1 overflow-y-auto p-4" ref={containerRef}>
      <h3 className="text-lg font-semibold mb-4">Conversation</h3>

      <div className="space-y-3">
        {conversationHistory && conversationHistory.length > 0 ? (
          conversationHistory.map((message, index) => (
            <Message
              key={index}
              role={message.role}
              content={message.content}
              tool_calls={message.tool_calls}
              tool_call_id={message.tool_call_id}
            />
          ))
        ) : (
          <p className="text-gray-500 text-sm text-center py-4">
            No messages yet. Start a conversation!
          </p>
        )}
      </div>
    </div>
  );
};

export default Conversation;
