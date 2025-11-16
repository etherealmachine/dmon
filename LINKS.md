# Linking GameNotes to PDF HTML Content

## Problem Statement

We want to link from GameNote records (e.g., an NPC note for "Hafkris") to specific locations in rendered PDF HTML content. This allows DMs to quickly jump from their notes to relevant sections in source material.

## Current State

### GameNote Model
- Has fields: `title`, `content`, `note_type`, `stats`, `actions`, `history`
- Belongs to `game`
- No direct relationship to PDFs

### PDF Model
- Has `html_content` field containing rendered HTML from pdftohtml
- HTML structure:
  - Pages wrapped in `<div id="pageN-div">` (e.g., `page9-div`, `page10-div`)
  - Text in positioned `<p>` tags with inline styles
  - Background images for each page
- Example: Hafkris NPC appears on pages 9-12 with 61 total mentions

### Current PDF HTML View (`app/views/pdfs/html.html.erb`)
- Displays HTML content with zoom controls
- Loads custom fonts via @font-face
- No anchor navigation or text highlighting

## Solution Options

### Option 1: Simple Page References (Quick Win)
**Implementation:**
- Add `pdf_id` and `page_number` fields to GameNote
- Link to existing page anchors: `pdf_html_path(pdf, anchor: "page9-div")`

**Pros:**
- Minimal changes required
- No HTML modification needed
- Easy to implement and maintain

**Cons:**
- Not granular - links to top of page
- No way to highlight specific content
- Limited flexibility

### Option 2: Enhanced HTML with Custom Anchors
**Implementation:**
- Post-process HTML to add semantic anchor IDs
- Add method `Pdf#add_anchors_to_html` to inject IDs
- Store enhanced HTML separately or on-the-fly

Example transformations:
```ruby
# Find headers/sections and add IDs
"<p class='ft92-s8'>Hafkris's State of Mind</p>"
# Becomes:
"<p id='hafkris-state-of-mind' class='ft92-s8'>Hafkris's State of Mind</p>"
```

**Pros:**
- Very precise linking
- Semantic, readable anchor IDs
- Better UX with exact positioning

**Cons:**
- Requires HTML processing
- Need to handle HTML regeneration (cache invalidation)
- More complex maintenance

### Option 3: Text-Based Search with Highlighting
**Implementation:**
- Store PDF ID + page + search term in GameNote
- Use JavaScript to find and highlight text on page load
- URL format: `pdf_html_path(pdf, page: 9, q: "Hafkris")`

**Pros:**
- No HTML modification required
- Flexible - works with any text
- Can highlight multiple occurrences
- User can see all matches

**Cons:**
- More complex frontend logic
- Highlighting might not be exact
- Performance considerations for long documents

### Option 4: JSONB References Array (Recommended)
**Implementation:**
- Add `pdf_references` JSONB column to `game_notes`
- Store array of reference objects:
```json
{
  "pdf_references": [
    {
      "pdf_id": 3,
      "page": 9,
      "anchor": "hafkris-intro",
      "label": "Beach Scene",
      "text_snippet": "staggering up and down the beach, is Hafkris",
      "highlight": "Hafkris"
    },
    {
      "pdf_id": 3,
      "page": 10,
      "anchor": "hafkris-state",
      "label": "Mental State",
      "text_snippet": "Hafkris is drunk out of his mind",
      "highlight": "drunk"
    }
  ]
}
```

**Pros:**
- Flexible - supports multiple references per note
- Can evolve without schema changes
- Supports both page-level and anchor-level linking
- Can include context (labels, snippets)
- Best long-term solution

**Cons:**
- Requires migration
- More complex data structure
- Need helper methods for manipulation

## Recommended Implementation Plan

### Phase 1: Foundation (MVP)
1. **Migration**: Add `pdf_references` JSONB column to `game_notes`
   ```ruby
   add_column :game_notes, :pdf_references, :jsonb, default: []
   ```

2. **Model Methods**:
   ```ruby
   # GameNote model
   def add_pdf_reference(pdf_id:, page:, **options)
     self.pdf_references ||= []
     self.pdf_references << {
       pdf_id: pdf_id,
       page: page,
       **options
     }
   end

   def references_for_pdf(pdf)
     (pdf_references || []).select { |ref| ref['pdf_id'] == pdf.id }
   end
   ```

3. **View Updates**:
   - Add reference links to GameNote show page
   - Display as clickable chips/badges
   - Link format: `pdf_html_path(pdf, anchor: "page#{page}-div")`

4. **PDF View Enhancement**:
   - Update `pdfs/html.html.erb` to handle URL fragments
   - Add JavaScript to scroll to anchor on page load

### Phase 2: Enhanced Linking
1. **HTML Anchor Injection**:
   ```ruby
   # Pdf model
   def enhanced_html_content
     return html_content unless html_content.present?

     # Parse HTML
     doc = Nokogiri::HTML.fragment(html_content)

     # Find and enhance specific elements
     # Example: Add IDs to headers with class ft92-s8
     doc.css('.ft92-s8, .ft91-s8').each do |header|
       text = header.text.strip
       anchor_id = text.parameterize
       header['id'] = anchor_id unless anchor_id.blank?
     end

     doc.to_html
   end
   ```

2. **Update view** to use `enhanced_html_content` or add anchors on-the-fly

### Phase 3: Search & Highlight
1. **Add search parameter support**:
   - URL: `pdf_html_path(pdf, anchor: "page9-div", highlight: "Hafkris")`

2. **JavaScript enhancement**:
   ```javascript
   // Highlight search terms
   function highlightText(searchTerm) {
     const content = document.getElementById('pdf-content');
     const regex = new RegExp(`(${searchTerm})`, 'gi');

     content.querySelectorAll('p').forEach(p => {
       if (p.textContent.match(regex)) {
         p.innerHTML = p.innerHTML.replace(regex,
           '<mark>$1</mark>');
       }
     });
   }
   ```

3. **Auto-scroll to first highlight**

## Usage Examples

### Example 1: Hafkris NPC Note
```ruby
hafkris_note = GameNote.find_by(title: "Hafkris")

# Add references to key sections
hafkris_note.add_pdf_reference(
  pdf_id: pdf.id,
  page: 9,
  label: "Initial Encounter",
  text_snippet: "staggering up and down the beach",
  highlight: "Hafkris"
)

hafkris_note.add_pdf_reference(
  pdf_id: pdf.id,
  page: 9,
  anchor: "hafkris-state-of-mind",
  label: "Mental State",
  text_snippet: "Hafkris is drunk out of his mind"
)

hafkris_note.add_pdf_reference(
  pdf_id: pdf.id,
  page: 9,
  anchor: "hafkris-combat-stats",
  label: "Combat Stats",
  text_snippet: "AC: 6, HD: 1 (hp 8)"
)

hafkris_note.save!
```

### Example 2: View Template
```erb
<%# app/views/game_notes/show.html.erb %>
<% if @note.pdf_references.present? %>
  <div class="pdf-references">
    <h3>Related PDF Sections</h3>
    <div class="flex gap-2 flex-wrap">
      <% @note.pdf_references.each do |ref| %>
        <% pdf = Pdf.find(ref['pdf_id']) %>
        <%= link_to pdf_html_path(pdf, anchor: "page#{ref['page']}-div", highlight: ref['highlight']),
                    class: "badge badge-outline" do %>
          <%= ref['label'] || "Page #{ref['page']}" %>
        <% end %>
      <% end %>
    </div>
  </div>
<% end %>
```

## Technical Considerations

### URL Fragment Handling
- Ensure `pdfs/html.html.erb` preserves URL fragments
- Use `scroll-margin-top` CSS for proper positioning with zoom controls

### Performance
- For large PDFs, consider lazy-loading or pagination
- Cache enhanced HTML if using Option 2
- Index `pdf_references` for faster queries if needed

### User Experience
- Visual indicator when jumping to highlighted section
- Breadcrumb or "back to note" button in PDF view
- Preview tooltip on hover showing text snippet

### Data Integrity
- Handle PDF deletion (remove references or keep for audit)
- Validate PDF exists when adding reference
- Consider soft-delete for PDFs referenced by notes

## Future Enhancements

1. **Bi-directional Linking**: Show which notes reference a PDF section
2. **Smart Reference Suggestions**: Use AI to suggest relevant PDF sections for notes
3. **Reference Clustering**: Group related references together
4. **Annotation Layer**: Allow inline comments/highlights in PDF view
5. **Reference Validation**: Check if text snippet still exists after PDF update
6. **Export**: Include PDF references when exporting notes

## Related Files

- `app/models/game_note.rb` - GameNote model
- `app/models/pdf.rb` - Pdf model
- `app/views/pdfs/html.html.erb` - PDF HTML viewer
- `app/views/game_notes/show.html.erb` - GameNote display

## Research Notes

### Hafkris Case Study
- Appears 61 times across the PDF
- Main content on pages 9-12
- Key sections:
  - Page 9: Initial description, "Hafkris's State of Mind" header
  - Page 9-10: Combat stats, attacking strategies
  - Page 11: "If Hafkris is Defeated" scenarios
  - Page 12: Battle interactions

### HTML Structure
- Generated by pdftohtml with `-zoom 3.0`
- Positioned paragraphs with absolute coordinates
- Font classes (ft35-s2, ft80-s7, etc.)
- Headers typically use larger font classes (ft92-s8, ft91-s8)
