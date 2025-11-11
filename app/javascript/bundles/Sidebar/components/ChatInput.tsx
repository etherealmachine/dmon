import React, { useState, FormEvent } from 'react';

interface ChatInputProps {
  gameId: number;
  model: string;
  onSubmit: (input: string, contextItems: string[], model: string) => void;
  isProcessing: boolean;
  selectedNoteGlobalIds?: string[];
}

const ALLOWED_MODELS = [
  'gpt-5',
  'gpt-5-nano',
  'claude-haiku-4-5-20251001'
];

const ChatInput: React.FC<ChatInputProps> = ({ gameId, model, onSubmit, isProcessing, selectedNoteGlobalIds = [] }) => {
  const [input, setInput] = useState('');
  const [selectedModel, setSelectedModel] = useState(model);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();

    if (isProcessing) {
      return;
    }

    if (!input || input.trim() === '') {
      return;
    }

    // Use selectedNoteGlobalIds from props and selectedModel from state
    onSubmit(input, selectedNoteGlobalIds, selectedModel);
    setInput('');
  };

  return (
    <div className="border-t border-gray-200 p-4 flex-shrink-0">
      <form onSubmit={handleSubmit} className="space-y-3">
        <div>
          <label htmlFor="model" className="block text-xs font-medium text-gray-700 mb-1">
            AI Model
          </label>
          <select
            id="model"
            value={selectedModel}
            onChange={(e) => setSelectedModel(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm mb-3"
          >
            {ALLOWED_MODELS.map((m) => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
        </div>
        <div>
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask anything..."
            rows={3}
            disabled={isProcessing}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none text-sm"
          />
        </div>
        <button
          type="submit"
          disabled={isProcessing}
          className="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded-lg transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isProcessing ? 'Processing...' : 'Send'}
        </button>
      </form>
    </div>
  );
};

export default ChatInput;
