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
            <a
              key={pdf.id}
              href={pdf.url}
              className="block bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-4 border border-gray-200"
            >
              <div className="flex items-start space-x-3">
                {/* PDF Icon */}
                <div className="flex-shrink-0 w-12 h-12 bg-red-100 rounded-lg flex items-center justify-center">
                  <svg className="w-6 h-6 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                  </svg>
                </div>

                {/* PDF Info */}
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-semibold text-gray-900 truncate mb-1">
                    {pdf.name}
                  </h4>
                  {pdf.description && (
                    <p className="text-xs text-gray-600 line-clamp-2">
                      {pdf.description}
                    </p>
                  )}
                  {pdf.image_count > 0 && (
                    <p className="text-xs text-gray-500 mt-1">
                      {pdf.image_count} images
                    </p>
                  )}
                </div>
              </div>
            </a>
          ))}

          {/* Upload New PDF Card */}
          <div className="bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-4 border-2 border-dashed border-gray-300">
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
              <div className="flex-shrink-0 w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                <svg className="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v16m8-8H4"></path>
                </svg>
              </div>
              <h4 className="text-sm font-semibold text-gray-900 text-center mb-3">Add New PDF</h4>
              <input
                type="file"
                name="pdf[pdf]"
                accept="application/pdf"
                className="block w-full text-xs text-gray-500 file:mr-2 file:py-2 file:px-3 file:rounded file:border-0 file:text-xs file:font-medium file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100 mb-3"
              />
              <button
                type="submit"
                className="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded-lg transition-colors cursor-pointer text-sm"
              >
                Add PDF
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PdfCards;
