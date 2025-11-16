# PDF to HTML Conversion - Known Issues

This document tracks known issues and limitations with our PDF to HTML conversion process using `pdftohtml`.

## 1. Missing Apostrophes and Special Characters

**Status:** Known Limitation - Cannot be easily fixed

**Description:**
Text extracted from PDFs often shows missing apostrophes, quotes, and other punctuation marks. For example:
- "don't" appears as "dont"
- "can't" appears as "cant"
- "you'll" appears as "youll"

**Root Cause:**
The issue originates from the PDF files themselves, not our conversion process. Many PDFs (especially older ones) use Type 1 fonts with custom character encodings that lack proper Unicode mapping tables (ToUnicode CMap).

When running `pdffonts` on affected PDFs, you'll see:
```
name                     type        encoding    emb sub uni object ID
MSTT31c543              Type 1C      Custom      yes no  no      19  0
```

The "uni: no" indicates no Unicode mapping exists in the PDF, meaning text extraction tools cannot properly decode characters.

**Verification:**
Even basic PDF text extraction tools fail on these files:
- `pdftohtml` (raw output): shows "cant" instead of "can't"
- `pdftotext`: shows "cant" instead of "can't"
- `mutool draw -F txt`: produces garbage characters (�)

**Impact:**
- Visual rendering is correct (background images show proper text)
- HTML text layer has missing punctuation
- Search functionality may be affected
- Copy/paste from the rendered page will have missing characters

**Possible Solutions:**
1. **Accept limitation** (Current approach) - Document that PDFs without Unicode mappings won't extract text perfectly
2. **Manual encoding analysis** - Analyze each PDF's font encoding tables and build custom character mappings (very complex, PDF-specific, not scalable)
3. **OCR fallback** - For PDFs with encoding issues, use OCR to extract text (slow, less accurate, resource-intensive)
4. **Hybrid approach** - Use background images for display + OCR for searchable text layer

**Recommendation:**
Accept this as a known limitation for now. The visual rendering remains correct since `pdftohtml` generates background images. Users can still read the content, but text extraction for search/copy will be imperfect.

---

## 2. Italic Text Positioning Issues

**Status:** Known Issue - Tradeoff between visual styling and positioning accuracy

**Description:**
When we detect and mark italic fonts with CSS `font-style: italic`, the text sometimes appears slightly offset to the right compared to its intended position.

**Root Cause:**
This is a "double italic" rendering issue:
1. PDF fonts often have italic glyph shapes baked into the font file itself (glyphs are already drawn slanted)
2. When we add CSS `font-style: italic`, browsers apply an additional synthetic slant transformation
3. This causes browsers to adjust metrics and positioning, resulting in text being offset from where `pdftohtml` calculated it should appear
4. The positioning was calculated by `pdftohtml` based on the original font metrics, which assumed no additional slanting

**Technical Details:**
- The fonts have `ItalicAngle: 0` in their metadata (despite having italic glyphs)
- Without CSS styling, browsers render the pre-slanted glyphs at correct positions
- With CSS `font-style: italic`, browsers apply synthetic italic on top of already-italic glyphs
- This double transformation causes the horizontal positioning offset

**Tradeoff:**
- **With CSS `font-style: italic`**: Text clearly appears italic, but may be positioned slightly to the right
- **Without CSS `font-style: italic`**: Text positioning is accurate, but italic text may not be as visually distinct (depends on how pronounced the glyph slant is)

**Current Implementation:**
We apply CSS `font-style: italic` to detected italic fonts to ensure they are visually distinguishable, accepting the minor positioning offset as a tradeoff for better visual styling.

**Detection Method:**
We detect italic fonts using naming patterns:
- Fonts with "italic", "oblique", "ital", "obli" in their name
- Common italic naming patterns like "FFLMLO" (italic) vs "FFLMLK" (regular)
- Italic markers in font name prefixes

**Alternative Approaches Considered:**
1. ~~Set italic angle in font file metadata~~ - Causes same positioning issues
2. ~~Don't apply CSS styling~~ - Makes italic text less distinguishable
3. **Current approach**: Apply CSS styling, accept positioning offset - Best user experience for readability

---

## 3. Font Extraction and Rebuilding

**Process:**
1. Use `pdftohtml` to convert PDF to HTML with embedded fonts
2. Extract fonts from PDF using `mutool extract`
3. Rebuild font cmap tables using FontForge to map glyphs by index (GID)
4. Convert CFF fonts to OTF for browser compatibility
5. Attach processed fonts to Active Storage

**Why Rebuild Fonts:**
- `mutool extract` strips cmap tables from fonts
- Without proper cmap tables, browsers cannot render text
- We map glyphs by position (GID) to match `pdftohtml`'s character code output
- This preserves the visual accuracy of text rendering

**Known Limitation:**
The GID-based mapping approach works for most characters but may not capture all special characters if the original PDF's encoding is non-standard (see Issue #1).

---

## Testing

To verify these issues with a specific PDF:

```bash
# Check font encoding
rails runner "pdf = Pdf.find(ID); pdf.pdf.open { |f| puts \`pdffonts #{f.path}\` }"

# Test text extraction with various tools
rails runner "pdf = Pdf.find(ID); pdf.pdf.open { |f| puts \`pdftotext #{f.path} -\` }"

# Check for specific text patterns
rails runner "html = Pdf.find(ID).html_content; puts html" | grep -E "don.t|can.t"
```
