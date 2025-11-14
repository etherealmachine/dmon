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
  has_many_attached :images, dependent: :purge
  has_many_attached :fonts

  validates :pdf, presence: true, on: :create
  validate :pdf_content_type, on: :create

  after_commit :enqueue_jobs, on: :create
  before_destroy :cleanup_shared_image_attachments

  def parse_pdf
    extract_text
    refine_text
    extract_html
    extract_images
    extract_metadata
    classify_images
  end

  def refine_text
    RefineText.new(self).call
  end

  def classify_images(reclassify: false)
    raise "No images to classify" if images.blank?

    images.each do |image|
      # Skip images not from pdfimages
      next unless image.blob.metadata['source'] == 'pdfimages'

      # Skip if already classified unless reclassify flag is set
      next if already_classified?(image) && !reclassify

      ClassifyImage.new(
        image,
        game.user.preferred_model,
        text_context: text_content
      ).classify
    end
  end

  def extract_metadata
    ExtractMetadata.new(self).call
  end

  def extract_text
    pdf.open do |tempfile|
      text = `pdf2txt.py #{tempfile.path}`
      update!(text_content: text)
    end
  end

  def extract_html
    PdfToHtml.new(self).call
  end

  def extract_images
    pdf.open do |tempfile|
      Dir.mktmpdir do |tmpdir|
        # Use PDF filename (without extension) as the base for output prefix
        base_filename = File.basename(pdf.filename.to_s, '.pdf')
        output_prefix = File.join(tmpdir, base_filename)

        # Extract images using pdfimages
        system('pdfimages', '-all', tempfile.path, output_prefix)

        # Attach all extracted images
        Dir.glob("#{output_prefix}*").sort.each_with_index do |image_path, index|
          next unless File.file?(image_path)

          ext = File.extname(image_path).downcase
          # Use Marcel to detect content type from file content
          content_type = Marcel::MimeType.for(Pathname.new(image_path))

          filename = "#{base_filename}_#{index}#{ext}"

          # Check for duplicate: same source, filename, and file size
          file_size = File.size(image_path)
          existing = images.find do |img|
            img.metadata['source'] == 'pdfimages' &&
              img.filename.to_s == filename &&
              img.byte_size == file_size
          end

          next if existing

          images.attach(
            io: File.open(image_path),
            filename: filename,
            content_type: content_type,
            metadata: {
              source: 'pdfimages',
              extraction_index: index
            }
          )
        end
      end
    end
  end

  def enqueue_jobs
    PdfJob.perform_later(id, :parse_pdf)
  end

  private

  def already_classified?(image)
    image.blob.metadata['classification'].present? &&
      image.blob.metadata['classified_at'].present?
  end

  def pdf_content_type
    return unless pdf.attached?

    if pdf.content_type != 'application/pdf'
      errors.add(:pdf, 'must be a PDF file')
    end
  end

  # Remove any GameNote attachments that reference this PDF's image blobs
  # This prevents orphaned attachments after the PDF's images are purged
  def cleanup_shared_image_attachments
    return unless images.attached?

    # Get all blob IDs from this PDF's images
    blob_ids = images.map(&:blob_id)

    # Find and destroy all ActiveStorage::Attachment records that:
    # 1. Belong to GameNote records
    # 2. Reference these blob IDs
    # 3. Are NOT the original attachments on this PDF
    ActiveStorage::Attachment
      .where(record_type: 'GameNote', blob_id: blob_ids)
      .where.not(record_id: id, record_type: 'Pdf')
      .destroy_all
  end
end
