import React, { useState, useEffect, useRef } from 'react';
import GameNotes from '../../GameNotes/components/GameNotes';
import Sidebar from '../../Sidebar/components/Sidebar';
import PdfCards from './PdfCards';
import MusicTracks from './MusicTracks';

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
  images?: string[];
}

interface Pdf {
  id: number;
  name: string;
  description?: string;
  image_count: number;
  url: string;
}

interface MusicTrack {
  id: number;
  filename: string;
  byte_size: number;
  url: string;
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
  pdfs: Pdf[];
  musicTracks: MusicTrack[];
  notes: Note[];
  selectedNoteIds: string[];
  plan: PlanItem[];
  model: string;
  conversationHistory: ConversationMessage[];
}

const GamePage: React.FC<GamePageProps> = ({
  gameId,
  pdfs,
  musicTracks,
  notes: initialNotes,
  selectedNoteIds: initialSelectedNoteIds,
  plan,
  model,
  conversationHistory
}) => {
  // Lift the selected notes state to this parent component
  const [selectedNoteGlobalIds, setSelectedNoteGlobalIds] = useState<string[]>(initialSelectedNoteIds);
  const [showDropdown, setShowDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const handleSelectionChange = (noteGlobalId: string, selected: boolean) => {
    setSelectedNoteGlobalIds(prev => {
      if (selected) {
        return [...prev, noteGlobalId];
      } else {
        return prev.filter(id => id !== noteGlobalId);
      }
    });
  };

  const handleDownload = () => {
    window.location.href = `/games/${gameId}/download`;
    setShowDropdown(false);
  };

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowDropdown(false);
      }
    };

    if (showDropdown) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [showDropdown]);

  return (
    <div className="flex h-[calc(100vh-4rem)]">
      {/* Main Panel */}
      <div className="flex-1 flex flex-col overflow-y-auto bg-gray-50 py-8 gap-4 relative">
        {/* Settings Dropdown */}
        <div className="absolute top-4 left-4 z-10" ref={dropdownRef}>
          <button
            onClick={() => setShowDropdown(!showDropdown)}
            className="p-2 bg-white rounded-full shadow-md hover:bg-gray-100 transition-colors"
            title="Game settings"
          >
            <svg
              className="w-5 h-5 text-gray-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
          </button>

          {/* Dropdown Menu */}
          {showDropdown && (
            <div className="absolute left-0 mt-2 w-48 bg-white rounded-md shadow-lg py-1 z-20">
              <button
                onClick={handleDownload}
                className="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 transition-colors"
              >
                <div className="flex items-center">
                  <svg
                    className="w-4 h-4 mr-2"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                    />
                  </svg>
                  Download Game
                </div>
              </button>
            </div>
          )}
        </div>

        <PdfCards pdfs={pdfs} gameId={gameId} />
        <MusicTracks musicTracks={musicTracks} gameId={gameId} />
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
