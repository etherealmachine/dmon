import React, { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

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
  images?: string[];
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
  images,
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
  const [editingStatKey, setEditingStatKey] = useState<string | null>(null);
  const [editingStatValue, setEditingStatValue] = useState<string>('');
  const [showImagePicker, setShowImagePicker] = useState(false);
  const [availableImages, setAvailableImages] = useState<Array<{
    pdf_id: number;
    pdf_name: string;
    images: Array<{ pdf_id: number; image_index: number; url: string }>;
  }>>([]);

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

  const handleStatClick = (key: string, value: any) => {
    setEditingStatKey(key);
    setEditingStatValue(String(value));
  };

  const handleStatKeyDown = async (e: React.KeyboardEvent, key: string) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      await handleStatUpdate(key);
    } else if (e.key === 'Escape') {
      setEditingStatKey(null);
      setEditingStatValue('');
    }
  };

  const handleStatUpdate = async (key: string) => {
    // Get the current value and compare
    const currentValue = stats?.[key];
    if (String(currentValue) === editingStatValue) {
      // No change, just cancel editing
      setEditingStatKey(null);
      setEditingStatValue('');
      return;
    }

    const formData = new FormData();
    formData.append('stat_key', key);
    formData.append('stat_value', editingStatValue);

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/update_stat`, {
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
        setEditingStatKey(null);
        setEditingStatValue('');
      } else {
        alert(`Failed to update stat: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error updating stat:', error);
      alert('Failed to update stat');
    }
  };

  const handleDeleteStat = async (key: string) => {
    if (!confirm(`Are you sure you want to delete the stat "${key}"?`)) {
      return;
    }

    const formData = new FormData();
    formData.append('stat_key', key);

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/delete_stat`, {
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
        alert(`Failed to delete stat: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error deleting stat:', error);
      alert('Failed to delete stat');
    }
  };

  const handleDeleteAction = async (actionIndex: number) => {
    if (!confirm('Are you sure you want to delete this action?')) {
      return;
    }

    const formData = new FormData();
    formData.append('action_index', actionIndex.toString());

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/delete_action`, {
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
        alert(`Failed to delete action: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error deleting action:', error);
      alert('Failed to delete action');
    }
  };

  const handleDeleteHistoryItem = async (historyIndex: number) => {
    if (!confirm('Are you sure you want to delete this history item?')) {
      return;
    }

    const formData = new FormData();
    formData.append('history_index', historyIndex.toString());

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/delete_history_item`, {
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
        alert(`Failed to delete history item: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error deleting history item:', error);
      alert('Failed to delete history item');
    }
  };

  const handleOpenImagePicker = async () => {
    setShowImagePicker(true);

    // Fetch available images if not already loaded
    if (availableImages.length === 0) {
      try {
        const response = await fetch(`/games/${gameId}/available_images`, {
          headers: {
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '',
            'Accept': 'application/json'
          },
        });

        const data = await response.json();

        if (data.pdfs) {
          setAvailableImages(data.pdfs.map((pdf: any) => ({
            pdf_id: pdf.id,
            pdf_name: pdf.name,
            images: pdf.images
          })));
        }
      } catch (error) {
        console.error('Error fetching available images:', error);
        alert('Failed to load available images');
      }
    }
  };

  const handleAttachImage = async (pdfId: number, imageIndex: number) => {
    const formData = new FormData();
    formData.append('pdf_id', pdfId.toString());
    formData.append('image_index', imageIndex.toString());

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/attach_image`, {
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
        setShowImagePicker(false);
      } else {
        alert(`Failed to attach image: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error attaching image:', error);
      alert('Failed to attach image');
    }
  };

  const handleDetachImage = async (imageIndex: number) => {
    if (!confirm('Are you sure you want to remove this image?')) {
      return;
    }

    const formData = new FormData();
    formData.append('image_index', imageIndex.toString());

    try {
      const response = await fetch(`/games/${gameId}/game_notes/${id}/detach_image`, {
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
        alert(`Failed to remove image: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error removing image:', error);
      alert('Failed to remove image');
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

          {/* Profile Image and Stats Section */}
          {(images && images.length > 0) || (stats && Object.keys(stats).length > 0) ? (
            <div className="mb-4 grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Stats Column */}
              {stats && Object.keys(stats).length > 0 && (
                <div>
                  <div className="text-xs font-medium text-gray-500 uppercase mb-2">Stats</div>
                  <div className="grid grid-cols-2 gap-2">
                    {Object.entries(stats).map(([key, value]) => (
                      <div key={key} className="group relative p-2 bg-blue-50 rounded border border-blue-200">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDeleteStat(key);
                          }}
                          className="absolute top-1 right-1 bg-red-500 hover:bg-red-600 text-white text-base font-bold w-5 h-5 rounded flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                          title="Delete stat"
                        >
                          ×
                        </button>
                        <div className="text-xs text-gray-600 mb-0.5 pr-6">{key}</div>
                        {editingStatKey === key ? (
                          <input
                            type="text"
                            value={editingStatValue}
                            onChange={(e) => setEditingStatValue(e.target.value)}
                            onKeyDown={(e) => handleStatKeyDown(e, key)}
                            onBlur={() => handleStatUpdate(key)}
                            autoFocus
                            className="text-lg font-semibold text-gray-900 bg-white border border-blue-300 rounded px-1 w-full"
                          />
                        ) : (
                          <div
                            className="text-lg font-semibold text-gray-900 cursor-pointer hover:bg-blue-100 rounded px-1"
                            onClick={() => handleStatClick(key, value)}
                            title="Click to edit"
                          >
                            {String(value)}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Profile Image Column */}
              {images && images.length > 0 && (
                <div className="relative rounded-lg overflow-hidden border-2 border-gray-300 group max-h-96 flex items-center justify-center bg-gray-50">
                  <img
                    src={images[0]}
                    alt="Profile"
                    className="max-h-96 w-full object-contain hover:scale-105 transition-transform cursor-pointer"
                    onClick={() => window.open(images[0], '_blank')}
                  />
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDetachImage(0);
                    }}
                    className="absolute top-2 right-2 bg-red-500 hover:bg-red-600 text-white text-base font-bold w-7 h-7 rounded flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                    title="Remove profile image"
                  >
                    ×
                  </button>
                </div>
              )}
            </div>
          ) : null}

          <div className="text-sm text-gray-900 prose prose-sm max-w-none">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
          </div>

          {/* Additional Images Section (excluding first image which is used as profile) */}
          {images && images.length > 1 && (
            <div className="mt-4 pt-4 border-t border-gray-200">
              <div className="flex items-center justify-between mb-2">
                <div className="text-xs font-medium text-gray-500 uppercase">Additional Images</div>
              </div>
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                {images.slice(1).map((imageUrl, index) => (
                  <div key={index + 1} className="group relative aspect-square rounded overflow-hidden border border-gray-200">
                    <img
                      src={imageUrl}
                      alt={`Note image ${index + 2}`}
                      className="w-full h-full object-cover hover:scale-105 transition-transform cursor-pointer"
                      onClick={() => window.open(imageUrl, '_blank')}
                    />
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDetachImage(index + 1);
                      }}
                      className="absolute top-1 right-1 bg-red-500 hover:bg-red-600 text-white text-base font-bold w-6 h-6 rounded flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                      title="Remove image"
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Add Image Button */}
          {(!images || images.length === 0) && (
            <div className="mt-4 pt-4 border-t border-gray-200">
              <div className="flex items-center justify-between mb-2">
                <div className="text-xs font-medium text-gray-500 uppercase">Images</div>
                <button
                  onClick={handleOpenImagePicker}
                  className="text-xs text-blue-600 hover:text-blue-800 font-medium"
                >
                  + Add Image
                </button>
              </div>
              <div className="text-xs text-gray-400 italic">No images attached</div>
            </div>
          )}

          {images && images.length > 0 && (
            <div className="mt-2 text-right">
              <button
                onClick={handleOpenImagePicker}
                className="text-xs text-blue-600 hover:text-blue-800 font-medium"
              >
                + Add More Images
              </button>
            </div>
          )}

          {actions && actions.length > 0 && (
            <div className="mt-4 pt-4 border-t border-gray-200">
              <div className="text-xs font-medium text-gray-500 uppercase mb-2">Actions</div>
              <div className="space-y-2">
                {actions.map((action, index) => (
                  <div key={index} className="group relative flex items-center justify-between p-2 bg-gray-50 rounded border border-gray-200">
                    <div className="flex-1">
                      <div className="text-sm font-medium text-gray-900">
                        {action.name || `Action ${index + 1}`}
                      </div>
                      {action.description && (
                        <div className="text-xs text-gray-600">{action.description}</div>
                      )}
                      {action.args && (
                        <div className="text-xs text-gray-600">Args: {JSON.stringify(action.args)}</div>
                      )}
                      <div className="text-xs text-gray-500 mt-1">Type: {action.type}</div>
                    </div>
                    <div className="flex gap-2 ml-3 flex-shrink-0">
                      <button
                        onClick={() => handleExecuteAction(index)}
                        className="bg-purple-500 hover:bg-purple-600 text-white text-xs font-medium py-1 px-3 rounded transition-colors"
                      >
                        Execute
                      </button>
                      <button
                        onClick={() => handleDeleteAction(index)}
                        className="bg-red-500 hover:bg-red-600 text-white text-base font-bold py-1 px-2 rounded transition-colors opacity-0 group-hover:opacity-100"
                        title="Delete action"
                      >
                        ×
                      </button>
                    </div>
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
                    className={`group relative p-3 bg-gray-50 rounded border ${
                      item.success ? 'border-green-200' : 'border-red-200'
                    }`}
                  >
                    <button
                      onClick={() => handleDeleteHistoryItem(index)}
                      className="absolute top-2 right-2 bg-red-500 hover:bg-red-600 text-white text-sm font-bold rounded w-5 h-5 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                      title="Delete history item"
                    >
                      ×
                    </button>
                    <div className="flex items-start justify-between mb-1 pr-8">
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

      {/* Image Picker Modal */}
      {showImagePicker && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" onClick={() => setShowImagePicker(false)}>
          <div className="bg-white rounded-lg p-6 max-w-4xl max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">Select an Image from PDFs</h3>
              <button
                onClick={() => setShowImagePicker(false)}
                className="text-gray-500 hover:text-gray-700 text-2xl font-bold"
              >
                ×
              </button>
            </div>

            {availableImages.length > 0 ? (
              <div className="space-y-6">
                {availableImages.map((pdf) => (
                  <div key={pdf.pdf_id}>
                    <h4 className="text-sm font-medium text-gray-700 mb-3">{pdf.pdf_name}</h4>
                    <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-2">
                      {pdf.images.map((image) => (
                        <div
                          key={`${image.pdf_id}-${image.image_index}`}
                          className="relative aspect-square rounded overflow-hidden border-2 border-gray-200 hover:border-blue-500 cursor-pointer transition-colors"
                          onClick={() => handleAttachImage(image.pdf_id, image.image_index)}
                        >
                          <img
                            src={image.url}
                            alt={`PDF image ${image.image_index + 1}`}
                            className="w-full h-full object-cover"
                          />
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center text-gray-500 py-8">
                <p>No images available from PDFs</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default GameNote;
