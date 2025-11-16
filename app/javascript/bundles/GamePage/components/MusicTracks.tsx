import React from 'react';

interface MusicTrack {
  id: number;
  filename: string;
  byte_size: number;
  url: string;
}

interface MusicTracksProps {
  musicTracks: MusicTrack[];
  gameId: number;
}

const MusicTracks: React.FC<MusicTracksProps> = ({ musicTracks, gameId }) => {
  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  };

  return (
    <div className="bg-gray-50">
      <div className="max-w-4xl mx-auto">
        <h3 className="text-lg font-semibold mb-3">Tracks</h3>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {/* Existing Music Track Cards */}
          {musicTracks.map((track) => (
            <a
              key={track.id}
              href={track.url}
              className="block bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-4 border border-gray-200"
            >
              <div className="flex items-start space-x-3">
                {/* Music Icon */}
                <div className="flex-shrink-0 w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center">
                  <svg className="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"></path>
                  </svg>
                </div>

                {/* Track Info */}
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-semibold text-gray-900 truncate mb-1">
                    {track.filename}
                  </h4>
                  <p className="text-xs text-gray-500">
                    {formatFileSize(track.byte_size)}
                  </p>
                </div>
              </div>
            </a>
          ))}

          {/* Upload New Music Track Card */}
          <div className="bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-4 border-2 border-dashed border-gray-300">
            <form
              action={`/games/${gameId}/music_tracks`}
              method="post"
              encType="multipart/form-data"
              className="h-full flex flex-col justify-center"
            >
              <input
                type="hidden"
                name="authenticity_token"
                value={document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''}
              />
              <div className="flex-shrink-0 w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                <svg className="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v16m8-8H4"></path>
                </svg>
              </div>
              <h4 className="text-sm font-semibold text-gray-900 text-center mb-3">Add Music Tracks</h4>
              <input
                type="file"
                name="music_tracks[]"
                accept="audio/mpeg,audio/mp3,audio/*"
                multiple
                className="block w-full text-xs text-gray-500 file:mr-2 file:py-2 file:px-3 file:rounded file:border-0 file:text-xs file:font-medium file:bg-purple-50 file:text-purple-700 hover:file:bg-purple-100 mb-3"
              />

              <button
                type="submit"
                className="w-full bg-purple-500 hover:bg-purple-600 text-white font-medium py-2 px-4 rounded-lg transition-colors cursor-pointer text-sm"
              >
                Add Tracks
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MusicTracks;
