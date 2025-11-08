class ParsePdfJob < ApplicationJob
  queue_as :default

  def perform(pdf_id, process_metadata: false)
    pdf = Pdf.find(pdf_id)
    pdf.parse_pdf(process_metadata: process_metadata)
    # Enqueue image classification after text is ready
    ClassifyImagesJob.perform_later(pdf_id)
  end
end

