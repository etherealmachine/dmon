import React from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface MessageProps {
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

const Message: React.FC<MessageProps> = ({ role, content, tool_calls, tool_call_id }) => {
  const isUser = role === 'user';

  // Don't render empty assistant messages (but do render tool messages)
  if (role === 'assistant' && !content?.trim() && !tool_calls?.length) {
    return null;
  }

  if (role === 'tool' && tool_call_id) {
    return null;
  }

  return (
    <div
      className={`${
        isUser ? 'bg-blue-50 border-blue-200' : 'bg-gray-50 border-gray-200'
      } border rounded-lg p-3`}
    >
      <div className="mb-1">
        <span
          className={`text-xs font-medium ${
            isUser ? 'text-blue-600' : 'text-gray-600'
          } uppercase`}
        >
          {role}
        </span>
      </div>

      {/* Show tool calls if present */}
      {tool_calls && tool_calls.length > 0 && (
        <div className="space-y-1 mb-2">
          {tool_calls.map((tool_call, index) => (
            <div key={index} className="flex items-center gap-2 text-sm text-gray-600">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
              </svg>
              <span className="font-mono">{tool_call.function.name}</span>
            </div>
          ))}
        </div>
      )}

      {/* Show content if present */}
      {content && content.trim() && (
        <div className="text-sm text-gray-700 prose prose-sm max-w-none">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
        </div>
      )}
    </div>
  );
};

export default Message;
