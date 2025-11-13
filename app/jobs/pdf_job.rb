class PdfJob < ApplicationJob
  queue_as :default

  def perform(pdf_id, method)
    pdf = Pdf.find(pdf_id)
    pdf.public_send(method)
  end
end
