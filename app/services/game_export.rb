require 'zip'
require 'fileutils'

class GameExport
  def initialize(game)
    @game = game
  end

  def call
    Dir.mktmpdir do |tmpdir|
      export_dir = File.join(tmpdir, 'export')
      FileUtils.mkdir_p(export_dir)

      # Create directory structure
      images_dir = File.join(export_dir, 'images')
      notes_dir = File.join(export_dir, 'notes')
      tracks_dir = File.join(export_dir, 'tracks')
      FileUtils.mkdir_p(images_dir)
      FileUtils.mkdir_p(notes_dir)
      FileUtils.mkdir_p(tracks_dir)

      # Export game notes as JSON
      export_notes(notes_dir)

      # Export each PDF with its content
      @game.pdfs.each do |pdf|
        export_pdf(pdf, export_dir, images_dir)
      end

      # Export music tracks
      export_music_tracks(tracks_dir)

      # Create zip file
      zip_path = File.join(tmpdir, "#{game_name}.zip")
      create_zip(export_dir, zip_path)

      # Read and return the zip file contents
      File.read(zip_path)
    end
  end

  private

  def game_name
    @game.name.presence || "game_#{@game.id}"
  end

  def export_notes(notes_dir)
    @game.game_notes.each_with_index do |note, index|
      filename = sanitize_filename("#{index + 1}_#{note.title || note.note_type || 'note'}.json")
      file_path = File.join(notes_dir, filename)

      note_data = {
        id: note.id,
        title: note.title,
        note_type: note.note_type,
        content: note.content,
        stats: note.stats,
        actions: note.actions,
        history: note.history,
        created_at: note.created_at,
        updated_at: note.updated_at
      }

      File.write(file_path, JSON.pretty_generate(note_data))
    end
  end

  def export_music_tracks(tracks_dir)
    return unless @game.music_tracks.attached?

    @game.music_tracks.each do |track|
      track_filename = track.filename.to_s
      track_path = File.join(tracks_dir, track_filename)

      # Copy the music track file
      track.open do |tempfile|
        FileUtils.cp(tempfile.path, track_path)
      end
    end
  end

  def export_pdf(pdf, export_dir, images_dir)
    # Create a directory for this PDF
    pdf_name = sanitize_filename(pdf.name || "pdf_#{pdf.id}")
    pdf_dir = File.join(export_dir, pdf_name)
    FileUtils.mkdir_p(pdf_dir)

    # Copy the PDF file
    if pdf.pdf.attached?
      pdf_filename = pdf.pdf.filename.to_s
      pdf_path = File.join(pdf_dir, pdf_filename)
      pdf.pdf.open do |tempfile|
        FileUtils.cp(tempfile.path, pdf_path)
      end
    end

    # Export text content as markdown
    if pdf.text_content.present?
      md_filename = "#{File.basename(pdf_name, '.*')}.md"
      md_path = File.join(pdf_dir, md_filename)
      File.write(md_path, pdf.text_content)
    end

    # Export images from pdfimages
    if pdf.images.attached?
      pdf.images.each do |image|
        # Only export images from pdfimages source
        next unless image.metadata['source'] == 'pdfimages'

        image_filename = image.filename.to_s
        image_path = File.join(images_dir, image_filename)

        # Avoid duplicate files
        unless File.exist?(image_path)
          image.open do |tempfile|
            FileUtils.cp(tempfile.path, image_path)
          end
        end
      end
    end

    # Export HTML with fonts and images
    if pdf.html_content.present?
      begin
        GameHtml.new(pdf, pdf_dir).call
      rescue => e
        Rails.logger.error("Failed to export HTML for PDF #{pdf.id}: #{e.message}")
      end
    end
  end

  def create_zip(source_dir, zip_path)
    Zip::File.open(zip_path, create: true) do |zipfile|
      # Add all files from the export directory
      Dir.glob(File.join(source_dir, '**', '*')).each do |file|
        next if File.directory?(file)

        # Calculate the relative path from the source directory
        relative_path = file.sub("#{source_dir}/", '')

        # Add file to zip
        zipfile.add(relative_path, file)
      end
    end
  end

  def sanitize_filename(filename)
    # Remove or replace characters that are problematic in filenames
    filename.gsub(/[^0-9A-Za-z.\-_ ]/, '_').gsub(/\s+/, '_')
  end
end
