import React from 'react';

interface Pdf {
  id: number;
  name: string;
  description?: string;
  image_count: number;
  url: string;
}

interface PdfCardsProps {
  pdfs: Pdf[];
  gameId: number;
}

const PdfCards: React.FC<PdfCardsProps> = ({ pdfs, gameId }) => {
  return (
    <div className="bg-gray-50">
      <div className="max-w-4xl mx-auto">
        <h3 className="text-lg font-semibold mb-3">PDFs</h3>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {/* Existing PDF Cards */}
          {pdfs.map((pdf) => (
            <div
              key={pdf.id}
              className="block bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-3 border border-gray-200 cursor-pointer"
              onClick={() => window.location.href = `/games/${gameId}/pdfs/${pdf.id}`}
            >
              <div className="flex items-start space-x-2 mb-2">
                {/* PDF Icon */}
                <div className="flex-shrink-0 w-8 h-8 bg-red-100 rounded flex items-center justify-center">
                  <svg className="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                  </svg>
                </div>

                {/* PDF Info */}
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-semibold text-gray-900 truncate mb-0.5">
                    {pdf.name}
                  </h4>
                  {pdf.description && (
                    <p className="text-xs text-gray-600 line-clamp-2">
                      {pdf.description}
                    </p>
                  )}
                  {pdf.image_count > 0 && (
                    <p className="text-xs text-gray-500 mt-0.5">
                      {pdf.image_count} images
                    </p>
                  )}
                </div>
              </div>

              {/* HTML View Button */}
              <a
                href={`/games/${gameId}/pdfs/${pdf.id}/html`}
                className="inline-block text-center bg-blue-500 hover:bg-blue-600 text-white text-xs font-medium py-1.5 px-3 rounded transition-colors"
                onClick={(e) => e.stopPropagation()}
              >
                View HTML
              </a>
            </div>
          ))}

          {/* Upload New PDF Card */}
          <div className="bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-3 border-2 border-dashed border-gray-300">
            <form
              action={`/games/${gameId}/pdfs`}
              method="post"
              encType="multipart/form-data"
              className="h-full flex flex-col justify-center"
            >
              <input
                type="hidden"
                name="authenticity_token"
                value={document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''}
              />
              <h4 className="text-xs font-semibold text-gray-900 text-center mb-2">Add PDF</h4>
              <input
                type="file"
                name="pdf[pdf]"
                accept="application/pdf"
                className="block w-full text-xs text-gray-500 file:mr-2 file:py-1.5 file:px-2 file:rounded file:border-0 file:text-xs file:font-medium file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100 mb-2"
              />
              <div className="text-center">
                <button
                  type="submit"
                  className="bg-blue-500 hover:bg-blue-600 text-white font-medium py-1.5 px-3 rounded transition-colors cursor-pointer text-xs"
                >
                  Add PDF
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PdfCards;
