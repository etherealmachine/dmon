class ClassifyImagesJob < ApplicationJob
  queue_as :default

  def perform(pdf_id, reclassify: false)
    pdf = Pdf.find(pdf_id)
    pdf.classify_images(reclassify: reclassify)
  end
end
