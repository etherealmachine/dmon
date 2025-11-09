# == Schema Information
#
# Table name: game_agents
#
#  id                   :bigint           not null, primary key
#  conversation_history :json
#  plan                 :json
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  game_id              :bigint           not null
#
# Indexes
#
#  index_game_agents_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
require "test_helper"

class GameAgentTest < ActiveSupport::TestCase
  setup do
    @game = games(:one)

    # NPC content for the adventure
    npc_content = <<~TEXT
      ## Human Bandit

      Medium humanoid (human), neutral evil

      **Armor Class** 12 (leather armor)
      **Hit Points** 11 (2d8 + 2)
      **Speed** 30 ft.

      **STR** 11 (+0)
      **DEX** 12 (+1)
      **CON** 12 (+1)
      **INT** 10 (+0)
      **WIS** 10 (+0)
      **CHA** 10 (+0)

      **Skills** Stealth +3
      **Senses** passive Perception 10
      **Languages** Common
      **Challenge** 1/8 (25 XP)

      ### Actions
      **Scimitar.** Melee Weapon Attack: +3 to hit, reach 5 ft., one target. Hit: 4 (1d6 + 1) slashing damage.
      **Light Crossbow.** Ranged Weapon Attack: +3 to hit, range 80/320 ft., one target. Hit: 5 (1d8 + 1) piercing damage.
    TEXT

    # Create a PDF with text content about an NPC
    @pdf = @game.pdfs.new(name: "Test Adventure")
    @pdf.pdf.attach(
      io: StringIO.new("Test PDF Content"),
      filename: "test_adventure.pdf",
      content_type: "application/pdf"
    )
    @pdf.save!

    # Attach the parsed text content
    @pdf.parsed_pdf.attach(
      io: StringIO.new(npc_content),
      filename: "test_adventure.txt",
      content_type: "text/plain"
    )

    @agent = @game.create_game_agent!
  end

  test "creates note with stats for human NPC using AI service" do
    # This is an integration test that makes a real API call
    skip "Skipping integration test - set INTEGRATION_TEST=1 to run" unless ENV['INTEGRATION_TEST']

    # Use model from environment variable or default to Claude
    @agent.model = ENV['INTEGRATION_TEST_MODEL'] || "claude-haiku-4-5-20251001"

    # Call the agent with a specific request to create a note for the Human Bandit from the adventure
    response_text = ""
    error_msg = nil
    chunks_received = []
    begin
      @agent.call("Create a character note for the Human Bandit described in the adventure. Include all the stats like HP, AC, STR, DEX, CON, INT, WIS, CHA.") do |chunk|
        chunks_received << chunk[:type]
        response_text += chunk[:content] if chunk[:type] == "content"
        error_msg = chunk[:error] if chunk[:type] == "error"
      end
    rescue => e
      error_msg = "#{e.class}: #{e.message}"
    end

    puts "Chunks received: #{chunks_received.inspect}" if ENV['DEBUG']

    # Verify that a note was created
    notes = @game.game_notes.reload
    assert notes.any?, "Expected at least one note to be created. Model: #{@agent.model}, Response: #{response_text[0..300]}, Error: #{error_msg}"

    # Debug: print note details
    if ENV['DEBUG']
      notes.each_with_index do |note, i|
        puts "\nNote #{i+1}:"
        puts "  ID: #{note.id}"
        puts "  Type: #{note.note_type}"
        puts "  Content length: #{note.content&.length}"
        puts "  Stats: #{note.stats.inspect}"
        puts "  Content preview: #{note.content&.[](0..200)}"
      end
    end

    # Find a note that has stats (either in stats field or mentions stats in content)
    note_with_stats = notes.find { |note| note.stats.present? }
    note_with_stat_content = notes.find { |note| note.content&.match?(/HP|Hit Points|Armor Class|AC|STR|DEX|CON/i) }

    # Accept either structured stats or stats mentioned in content
    # (Different models may structure the response differently)
    assert note_with_stats || note_with_stat_content,
      "Expected at least one note to have stats (in stats field) or stat content. Created #{notes.count} note(s)"

    # If we have structured stats, verify they're not empty
    if note_with_stats
      assert note_with_stats.stats.any?, "Expected stats to be non-empty"
    end

    # Verify some reasonable stat keys exist if we have structured stats
    if note_with_stats && note_with_stats.stats.any?
      stat_keys = note_with_stats.stats.keys.map(&:upcase)
      expected_stats = %w[HP AC STR DEX CON INT WIS CHA]
      assert (expected_stats & stat_keys).any?, "Expected at least one standard D&D stat (HP, AC, STR, DEX, CON, INT, WIS, CHA)"
    end
  end
end
