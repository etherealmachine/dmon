module ApplicationHelper
  def markdown(text)
    return "" if text.blank?

    options = {
      filter_html: false,
      hard_wrap: true,
      link_attributes: { rel: "nofollow", target: "_blank" },
      space_after_headers: true,
      fenced_code_blocks: true
    }

    extensions = {
      autolink: true,
      superscript: true,
      disable_indented_code_blocks: true,
      tables: true,
      strikethrough: true,
      underline: true,
      highlight: true,
      footnotes: true
    }

    renderer = Redcarpet::Render::HTML.new(options)
    markdown = Redcarpet::Markdown.new(renderer, extensions)

    markdown.render(text).html_safe
  end

  def breadcrumbs
    crumbs = []

    if defined?(@game) && @game.present? && @game.id.present?
      game_name = @game.name.presence || "Game ##{@game.id}"
      crumbs << { text: game_name, url: game_path(@game) }

      if defined?(@pdf) && @pdf.present?
        crumbs << { text: @pdf.name, url: game_pdf_path(@game, @pdf) }

        if defined?(@image) && @image.present?
          image_name = @image.filename.to_s
          crumbs << { text: image_name, url: game_pdf_image_path(@game, @pdf, @image.id) }
        end
      elsif defined?(@music_track) && @music_track.present?
        track_name = @music_track.filename || "Track ##{@music_track.id}"
        crumbs << { text: track_name, url: game_music_track_path(@game, @music_track) }
      end
    end

    crumbs
  end
end
