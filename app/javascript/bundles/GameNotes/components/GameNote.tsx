import React, { useState } from 'react';

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

interface GameNoteProps {
  id: number;
  globalId: string;
  title?: string;
  noteType: string;
  content: string;
  createdAt: string;
  stats?: Record<string, any>;
  actions?: Action[];
  history?: HistoryItem[];
  isSelected: boolean;
  gameId: number;
  onSelectionChange: (noteId: number, selected: boolean) => void;
  onDelete: (noteId: number) => void;
  onUpdate: (updatedNote: Note) => void;
}

const GameNote: React.FC<GameNoteProps> = ({
  id,
  globalId,
  title,
  noteType,
  content,
  createdAt,
  stats,
  actions,
  history,
  isSelected,
  gameId,
  onSelectionChange,
  onDelete,
  onUpdate,
}) => {
  const [isEditing, setIsEditing] = useState(false);
  const [editedTitle, setEditedTitle] = useState(title || '');
  const [editedContent, setEditedContent] = useState(content);
  const [editedNoteType, setEditedNoteType] = useState(noteType);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const noteTypes = [
    { label: 'Note', value: 'note' },
    { label: 'NPC', value: 'npc' },
    { label: 'Item', value: 'item' },
    { label: 'Context', value: 'context' },
  ];

  const handleEdit = () => {
    setIsEditing(true);
  };

  const handleCancel = () => {
    setIsEditing(false);
    setEditedTitle(title || '');
    setEditedContent(content);
    setEditedNoteType(noteType);
  };

  const handleSave = async () => {
    setIsSubmitting(true);

    const formData = new FormData();
    formData.append('game_note[title]', editedTitle);
    formData.append('game_note[content]', editedContent);
    formData.append('game_note[note_type]', editedNoteType);
    formData.append('_method', 'patch');

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
          'Accept': 'application/json'
        },
      });

      const data = await response.json();

      if (data.success && data.note) {
        setIsEditing(false);
        onUpdate(data.note);
      } else {
        alert(`Failed to update note: ${data.errors?.join(', ') || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error updating note:', error);
      alert('Failed to update note');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = async () => {
    if (!confirm('Are you sure you want to delete this note?')) {
      return;
    }

    const formData = new FormData();
    formData.append('_method', 'delete');

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
        },
      });

      if (response.ok) {
        onDelete(id);
      } else {
        alert('Failed to delete note');
      }
    } catch (error) {
      console.error('Error deleting note:', error);
      alert('Failed to delete note');
    }
  };

  const handleExecuteAction = async (actionIndex: number) => {
    const formData = new FormData();
    formData.append('action_index', actionIndex.toString());

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/call_action`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
          'Accept': 'application/json'
        },
      });

      const data = await response.json();

      if (data.success && data.note) {
        onUpdate(data.note);
      } else {
        alert(`Failed to execute action: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error executing action:', error);
      alert('Failed to execute action');
    }
  };

  const handleClearHistory = async () => {
    if (!confirm('Are you sure you want to clear the action history?')) {
      return;
    }

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/clear_history`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
          'Accept': 'application/json'
        },
      });

      const data = await response.json();

      if (data.success && data.note) {
        onUpdate(data.note);
      } else {
        alert(`Failed to clear history: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error clearing history:', error);
      alert('Failed to clear history');
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    });
  };

  const noteTypeColor = noteType === 'chat'
    ? 'bg-blue-100 text-blue-800'
    : 'bg-green-100 text-green-800';

  return (
    <div className="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
      {!isEditing ? (
        <>
          {/* Note View */}
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                className="rounded text-blue-600 focus:ring-blue-500"
                checked={isSelected}
                onChange={(e) => onSelectionChange(id, e.target.checked)}
              />
              <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${noteTypeColor}`}>
                {noteType}
              </span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500">{formatDate(createdAt)}</span>
              <button
                onClick={handleEdit}
                className="text-xs text-blue-600 hover:text-blue-800 font-medium"
              >
                Edit
              </button>
              <button
                onClick={handleDelete}
                className="text-xs text-red-600 hover:text-red-800 font-medium"
              >
                Delete
              </button>
            </div>
          </div>

          {title && (
            <div className="mb-2">
              <h4 className="text-lg font-bold text-gray-900">{title}</h4>
            </div>
          )}

          <div className="text-sm text-gray-900 prose prose-sm max-w-none">
            <div dangerouslySetInnerHTML={{ __html: content }} />
          </div>

          {stats && Object.keys(stats).length > 0 && (
            <div className="mt-4 pt-4 border-t border-gray-200">
              <div className="text-xs font-medium text-gray-500 uppercase mb-2">Stats</div>
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                {Object.entries(stats).map(([key, value]) => (
                  <div key={key} className="p-2 bg-blue-50 rounded border border-blue-200">
                    <div className="text-xs text-gray-600 mb-0.5">{key}</div>
                    <div className="text-lg font-semibold text-gray-900">{String(value)}</div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {actions && actions.length > 0 && (
            <div className="mt-4 pt-4 border-t border-gray-200">
              <div className="text-xs font-medium text-gray-500 uppercase mb-2">Actions</div>
              <div className="space-y-2">
                {actions.map((action, index) => (
                  <div key={index} className="flex items-center justify-between p-2 bg-gray-50 rounded border border-gray-200">
                    <div className="flex-1">
                      <div className="text-sm font-medium text-gray-900">
                        {action.name || `Action ${index + 1}`}
                      </div>
                      {action.description && (
                        <div className="text-xs text-gray-600">{action.description}</div>
                      )}
                      <div className="text-xs text-gray-500 mt-1">Type: {action.type}</div>
                    </div>
                    <button
                      onClick={() => handleExecuteAction(index)}
                      className="ml-3 bg-purple-500 hover:bg-purple-600 text-white text-xs font-medium py-1 px-3 rounded transition-colors"
                    >
                      Execute
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {history && history.length > 0 && (
            <div className="mt-4 pt-4 border-t border-gray-200">
              <div className="flex items-center justify-between mb-2">
                <div className="text-xs font-medium text-gray-500 uppercase">Action History</div>
                <button
                  onClick={handleClearHistory}
                  className="text-xs text-red-600 hover:text-red-800 font-medium"
                >
                  Clear History
                </button>
              </div>
              <div className="space-y-2">
                {history.map((item, index) => (
                  <div
                    key={index}
                    className={`p-3 bg-gray-50 rounded border ${
                      item.success ? 'border-green-200' : 'border-red-200'
                    }`}
                  >
                    <div className="flex items-start justify-between mb-1">
                      <div className={`text-xs font-medium ${
                        item.success ? 'text-green-700' : 'text-red-700'
                      }`}>
                        {(item.action_name || `Action ${index + 1}`).toUpperCase()}
                      </div>
                      <div className="text-xs text-gray-500">
                        {formatDate(item.timestamp)}
                      </div>
                    </div>

                    {item.action_description && (
                      <div className="text-xs text-gray-600 mb-2">
                        {item.action_description}
                      </div>
                    )}

                    {item.success && item.result && item.action_type === 'roll' && (
                      <>
                        <div className="text-sm font-medium text-gray-900 mb-1">
                          {item.result.dice_notation}: <span className="text-green-600">{item.result.total}</span>
                        </div>
                        <div className="text-xs text-gray-600">{item.result.breakdown}</div>
                      </>
                    )}

                    {!item.success && item.error && (
                      <div className="text-xs text-red-600">Error: {item.error}</div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      ) : (
        <>
          {/* Note Edit Form */}
          <div className="space-y-3">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Note Type</label>
              <select
                value={editedNoteType}
                onChange={(e) => setEditedNoteType(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
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
                value={editedTitle}
                onChange={(e) => setEditedTitle(e.target.value)}
                placeholder="e.g., Human Bandit, Magic Sword +1"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
                disabled={isSubmitting}
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Note Content</label>
              <textarea
                value={editedContent}
                onChange={(e) => setEditedContent(e.target.value)}
                rows={6}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none text-sm"
                disabled={isSubmitting}
              />
            </div>
            <div className="flex gap-2">
              <button
                onClick={handleSave}
                disabled={isSubmitting}
                className="bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSubmitting ? 'Saving...' : 'Update Note'}
              </button>
              <button
                onClick={handleCancel}
                disabled={isSubmitting}
                className="bg-gray-300 hover:bg-gray-400 text-gray-700 font-medium py-2 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Cancel
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

export default GameNote;
