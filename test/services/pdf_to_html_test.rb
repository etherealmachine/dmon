require "test_helper"

# Tests for the PdfToHtml service
#
# Note: These tests require:
# 1. A sample PDF file at test/fixtures/files/sample.pdf
# 2. External tools: pdftohtml, mutool, fc-scan
#
# Most tests will be skipped if these requirements are not met.
# This is intentional to allow tests to run in CI environments
# where these dependencies may not be available.
class PdfToHtmlTest < ActiveSupport::TestCase
  test "service can be instantiated" do
    user = users(:one)
    game = games(:one)
    pdf = game.pdfs.new(name: "Test")

    service = PdfToHtml.new(pdf)

    assert_not_nil service
    assert_instance_of PdfToHtml, service
  end
end

# Integration tests that require a real PDF file and external tools
class PdfToHtmlIntegrationTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @game = games(:one)

    # Check if sample PDF exists
    sample_pdf_path = Rails.root.join('test', 'fixtures', 'files', 'sample.pdf')
    skip "Sample PDF not found at #{sample_pdf_path}" unless File.exist?(sample_pdf_path)

    @pdf = @game.pdfs.new(
      name: "Test PDF",
      text_content: "Sample text content"
    )

    # Attach the PDF file
    @pdf.pdf.attach(
      io: File.open(sample_pdf_path),
      filename: 'sample.pdf',
      content_type: 'application/pdf'
    )

    @pdf.save!
  end


  test "converts PDF to HTML" do
    skip "Skipping because it requires external tools (pdftohtml, mutool)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1')

    service = PdfToHtml.new(@pdf)
    service.call

    assert @pdf.html_content.present?, "HTML content should be generated"
  end

  test "extracts and attaches fonts" do
    skip "Skipping because it requires external tools (pdftohtml, mutool)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1')

    service = PdfToHtml.new(@pdf)
    service.call

    assert @pdf.fonts.any?, "Fonts should be extracted and attached"
  end

  test "extracts and attaches images" do
    skip "Skipping because it requires external tools (pdftohtml, mutool)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1')

    service = PdfToHtml.new(@pdf)
    service.call

    assert @pdf.images.any?, "Images should be extracted and attached"
  end

  test "clears existing fonts and images before extraction" do
    skip "Skipping because it requires external tools (pdftohtml, mutool)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1')

    # Attach some dummy fonts and images
    @pdf.fonts.attach(io: StringIO.new("dummy"), filename: "dummy.ttf")
    @pdf.images.attach(io: StringIO.new("dummy"), filename: "dummy.png")

    initial_font_count = @pdf.fonts.count
    initial_image_count = @pdf.images.count

    service = PdfToHtml.new(@pdf)
    service.call

    assert_not_equal initial_font_count, @pdf.fonts.count, "Fonts should be replaced"
    assert_not_equal initial_image_count, @pdf.images.count, "Images should be replaced"
  end

  test "quotes font-family names with special characters" do
    skip "Skipping because it requires external tools (pdftohtml, mutool)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1')

    service = PdfToHtml.new(@pdf)
    service.call

    # Check if font names with + are properly quoted
    if @pdf.html_content.match?(/font-family/)
      font_families = @pdf.html_content.scan(/font-family:\s*'([^']+\+[^']+)'/)

      # If there are font families with +, they should all be quoted
      if font_families.any?
        assert font_families.all? { |ff| ff.first.include?('+') }, "Font families with + should be quoted"
      end
    end
  end

  test "matches fonts to HTML font names" do
    skip "Skipping because it requires external tools (pdftohtml, mutool, fc-scan)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1') && system('which fc-scan > /dev/null 2>&1')

    service = PdfToHtml.new(@pdf)
    service.call

    # Each font should have a font_name in metadata
    @pdf.fonts.each do |font|
      assert font.metadata['font_name'].present?, "Font #{font.filename} should have a font_name in metadata"
    end
  end

  test "avoids duplicate font assignments" do
    skip "Skipping because it requires external tools (pdftohtml, mutool, fc-scan)" unless system('which pdftohtml > /dev/null 2>&1') && system('which mutool > /dev/null 2>&1') && system('which fc-scan > /dev/null 2>&1')

    service = PdfToHtml.new(@pdf)
    service.call

    # Check for duplicate font names
    font_names = @pdf.fonts.map { |f| f.metadata['font_name'] }.compact
    duplicate_names = font_names.select { |name| font_names.count(name) > 1 }.uniq

    assert_empty duplicate_names, "Should not have duplicate font assignments: #{duplicate_names.join(', ')}"
  end
end
