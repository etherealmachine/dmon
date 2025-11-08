class ExtractMetadataJob < ApplicationJob
  queue_as :default

  def perform(pdf_id)
    pdf = Pdf.find(pdf_id)
    pdf.extract_metadata
  end
end
