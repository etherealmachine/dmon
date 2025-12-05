module GameAgentTools
  class RollDiceTool < RubyLLM::Tool
    description "Roll dice using standard RPG notation (e.g., '1d20', '2d6', '4d8+3'). Supports modifiers like +/- and advantage/disadvantage for d20 rolls."

    def name
      "roll_dice"
    end

    params({
      "type" => "object",
      "properties" => {
        "dice_notation" => {
          "type" => "string",
          "description" => "The dice to roll in standard notation (e.g., '1d20', '2d6', '4d8+3', '1d20+5')"
        },
        "advantage" => {
          "type" => "boolean",
          "description" => "For d20 rolls, roll twice and take the higher result"
        },
        "disadvantage" => {
          "type" => "boolean",
          "description" => "For d20 rolls, roll twice and take the lower result"
        },
        "description" => {
          "type" => "string",
          "description" => "Optional description of what the roll is for (e.g., 'attack roll', 'damage')"
        }
      },
      "required" => ["dice_notation"],
      "additionalProperties" => false
    })

    def initialize(game)
      @game = game
    end

    def execute(dice_notation:, advantage: nil, disadvantage: nil, description: nil)
      arguments = { "dice_notation" => dice_notation }
      arguments["advantage"] = advantage if advantage
      arguments["disadvantage"] = disadvantage if disadvantage
      arguments["description"] = description if description

      RollService.roll(arguments)
    rescue RollService::InvalidDiceNotation, RollService::InvalidDiceParameters => e
      { success: false, error: e.message }
    end
  end
end
