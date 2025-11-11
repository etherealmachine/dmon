import React, { useState } from 'react';
import GameNotes from '../../GameNotes/components/GameNotes';
import Sidebar from '../../Sidebar/components/Sidebar';

interface Action {
  name: string;
  description?: string;
  type: string;
  args?: any;
}

interface HistoryItem {
  action_name: string;
  action_description?: string;
  action_type: string;
  success: boolean;
  timestamp: string;
  result?: {
    dice_notation: string;
    total: number;
    breakdown: string;
  };
  error?: string;
}

interface Note {
  id: number;
  global_id: string;
  title?: string;
  note_type: string;
  content: string;
  created_at: string;
  stats?: Record<string, any>;
  actions?: Action[];
  history?: HistoryItem[];
}

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

interface GamePageProps {
  gameId: number;
  notes: Note[];
  selectedNoteIds: string[];
  plan: PlanItem[];
  model: string;
  conversationHistory: ConversationMessage[];
}

const GamePage: React.FC<GamePageProps> = ({
  gameId,
  notes: initialNotes,
  selectedNoteIds: initialSelectedNoteIds,
  plan,
  model,
  conversationHistory
}) => {
  // Lift the selected notes state to this parent component
  const [selectedNoteGlobalIds, setSelectedNoteGlobalIds] = useState<string[]>(initialSelectedNoteIds);

  const handleSelectionChange = (noteGlobalId: string, selected: boolean) => {
    setSelectedNoteGlobalIds(prev => {
      if (selected) {
        return [...prev, noteGlobalId];
      } else {
        return prev.filter(id => id !== noteGlobalId);
      }
    });
  };

  return (
    <div className="flex h-[calc(100vh-4rem)]">
      {/* Main Panel */}
      <div className="flex-1 overflow-y-auto p-8 bg-gray-50">
        <div className="max-w-4xl mx-auto">
          <GameNotes
            gameId={gameId}
            notes={initialNotes}
            selectedNoteIds={selectedNoteGlobalIds}
            onSelectionChange={handleSelectionChange}
          />
        </div>
      </div>

      {/* Sidebar */}
      <Sidebar
        gameId={gameId}
        plan={plan}
        model={model}
        conversationHistory={conversationHistory}
        selectedNoteGlobalIds={selectedNoteGlobalIds}
      />
    </div>
  );
};

export default GamePage;
