import React, { useState } from 'react';
import GameNote from './GameNote';

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

interface GameNotesProps {
  gameId: number;
  notes: Note[];
  selectedNoteIds?: string[];
}

const GameNotes: React.FC<GameNotesProps> = ({ gameId, notes: initialNotes, selectedNoteIds = [] }) => {
  const [notes, setNotes] = useState<Note[]>(initialNotes);
  const [selectedIds, setSelectedIds] = useState<Set<number>>(
    new Set(
      initialNotes
        .filter(note => selectedNoteIds.includes(note.global_id))
        .map(note => note.id)
    )
  );
  const [showNewNoteForm, setShowNewNoteForm] = useState(false);
  const [newNoteType, setNewNoteType] = useState('note');
  const [newNoteTitle, setNewNoteTitle] = useState('');
  const [newNoteContent, setNewNoteContent] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const noteTypes = [
    { label: 'Note', value: 'note' },
    { label: 'NPC', value: 'npc' },
    { label: 'Item', value: 'item' },
    { label: 'Context', value: 'context' },
  ];

  const handleSelectionChange = (noteId: number, selected: boolean) => {
    setSelectedIds(prev => {
      const newSet = new Set(prev);
      if (selected) {
        newSet.add(noteId);
      } else {
        newSet.delete(noteId);
      }
      return newSet;
    });
  };

  const handleDelete = (noteId: number) => {
    setNotes(prev => prev.filter(note => note.id !== noteId));
    setSelectedIds(prev => {
      const newSet = new Set(prev);
      newSet.delete(noteId);
      return newSet;
    });
  };

  const handleUpdate = (updatedNote: Note) => {
    // Update the note in state with the new data
    setNotes(prev => prev.map(note =>
      note.id === updatedNote.id ? updatedNote : note
    ));
  };

  const handleCreateNote = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);

    const formData = new FormData();
    formData.append('game_note[note_type]', newNoteType);
    formData.append('game_note[title]', newNoteTitle);
    formData.append('game_note[content]', newNoteContent);

    try {
      const response = await fetch(`/games/${gameId}/game_notes`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
          'Accept': 'application/json'
        },
      });

      const data = await response.json();

      if (data.success && data.note) {
        // Add the new note to the list
        setNotes(prev => [...prev, data.note]);
        // Reset form
        setShowNewNoteForm(false);
        setNewNoteTitle('');
        setNewNoteContent('');
        setNewNoteType('note');
      } else {
        alert(`Failed to create note: ${data.errors?.join(', ') || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error creating note:', error);
      alert('Failed to create note');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCancelNewNote = () => {
    setShowNewNoteForm(false);
    setNewNoteTitle('');
    setNewNoteContent('');
    setNewNoteType('note');
  };

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Game Notes</h3>
        <button
          onClick={() => setShowNewNoteForm(!showNewNoteForm)}
          className="bg-green-500 hover:bg-green-600 text-white text-sm font-medium py-2 px-4 rounded-lg transition-colors"
        >
          + New Note
        </button>
      </div>

      {/* New Note Form */}
      {showNewNoteForm && (
        <div className="mb-6 p-4 border border-gray-200 rounded-lg bg-gray-50">
          <form onSubmit={handleCreateNote} className="space-y-3">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Note Type</label>
              <select
                value={newNoteType}
                onChange={(e) => setNewNoteType(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent text-sm"
                disabled={isSubmitting}
              >
                {noteTypes.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Title (Optional)</label>
              <input
                type="text"
                value={newNoteTitle}
                onChange={(e) => setNewNoteTitle(e.target.value)}
                placeholder="e.g., Human Bandit, Magic Sword +1"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent text-sm"
                disabled={isSubmitting}
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Note Content</label>
              <textarea
                value={newNoteContent}
                onChange={(e) => setNewNoteContent(e.target.value)}
                placeholder="Your note content (supports markdown)..."
                rows={6}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent resize-none text-sm"
                disabled={isSubmitting}
                required
              />
            </div>
            <div className="flex gap-2">
              <button
                type="submit"
                disabled={isSubmitting}
                className="bg-green-500 hover:bg-green-600 text-white font-medium py-2 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSubmitting ? 'Creating...' : 'Create Note'}
              </button>
              <button
                type="button"
                onClick={handleCancelNewNote}
                disabled={isSubmitting}
                className="bg-gray-300 hover:bg-gray-400 text-gray-700 font-medium py-2 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Notes List */}
      {notes.length > 0 ? (
        <div className="space-y-4">
          {notes.map((note) => (
            <GameNote
              key={note.id}
              id={note.id}
              globalId={note.global_id}
              title={note.title}
              noteType={note.note_type}
              content={note.content}
              createdAt={note.created_at}
              stats={note.stats}
              actions={note.actions}
              history={note.history}
              isSelected={selectedIds.has(note.id)}
              gameId={gameId}
              onSelectionChange={handleSelectionChange}
              onDelete={handleDelete}
              onUpdate={handleUpdate}
            />
          ))}
        </div>
      ) : (
        <div className="text-center text-gray-500 py-8">
          <p>No notes yet.</p>
          <p className="text-sm mt-2">Notes created by the assistant will appear here.</p>
        </div>
      )}
    </div>
  );
};

export default GameNotes;
