# == Schema Information
#
# Table name: pdfs
#
#  id           :bigint           not null, primary key
#  description  :text
#  html_content :text
#  name         :string
#  text_content :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  game_id      :bigint           not null
#
# Indexes
#
#  index_pdfs_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
class Pdf < ApplicationRecord
  belongs_to :game
  has_one_attached :pdf
  has_many_attached :images

  validates :pdf, presence: true, on: :create
  validate :pdf_content_type, on: :create

  after_commit :enqueue_jobs, on: :create

  def extract_images
    return unless pdf.attached?

    # Create a temporary directory for extraction
    Dir.mktmpdir do |tmpdir|
      # Save PDF to temp file
      pdf_path = File.join(tmpdir, 'input.pdf')
      File.binwrite(pdf_path, pdf.download)

      # Extract images using pdfimages
      # -all: extract all image types
      output_prefix = File.join(tmpdir, 'image')
      system('pdfimages', '-all', pdf_path, output_prefix)

      # Attach all extracted images
      Dir.glob("#{output_prefix}*").each_with_index do |image_path, index|
        next unless File.file?(image_path)

        # Determine content type based on file extension
        ext = File.extname(image_path).downcase
        content_type = case ext
                      when '.jpg', '.jpeg' then 'image/jpeg'
                      when '.png' then 'image/png'
                      when '.ppm' then 'image/x-portable-pixmap'
                      when '.pbm' then 'image/x-portable-bitmap'
                      else 'application/octet-stream'
                      end

        images.attach(
          io: File.open(image_path),
          filename: "image_#{index}#{ext}",
          content_type: content_type
        )
      end
    end
  end

  def prune_images
    images.each do |image|
      should_delete = image.metadata['should_delete']
      image.purge if should_delete == true || should_delete == 'true'
    end
  end

  def classify_images(reclassify: false)
    extract_images if images.empty?
    ClassifyImages.new(self, reclassify:).call
    prune_images
  end

  def extract_metadata
    ExtractMetadata.new(self).call
  end

  def parse_pdf(process_metadata: true)
    # Extract text and HTML from the PDF
    pdf.open do |tempfile|
      # Extract text with pdf2txt.py
      text = `pdf2txt.py #{tempfile.path}`
      update!(text_content: text)
    end

    extract_html
    extract_metadata if process_metadata
  end

  def extract_html
    pdf.open do |tempfile|
      html = `pdftohtml -s #{tempfile.path}`
      update!(html_content: html)
    end
  end

  def enqueue_jobs
    ParsePdfJob.perform_later(id)
    # ClassifyImagesJob will be enqueued by ParsePdfJob after text is ready
  end

  private

  def pdf_content_type
    return unless pdf.attached?

    if pdf.content_type != 'application/pdf'
      errors.add(:pdf, 'must be a PDF file')
    end
  end
end
