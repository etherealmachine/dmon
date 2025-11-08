class RollService
  class InvalidDiceNotation < StandardError; end
  class InvalidDiceParameters < StandardError; end

  # @param input [String, Hash] Either a dice notation string (e.g., "2d6+3") or a hash with parameters
  # @option input [String] :dice_notation The dice notation (required if Hash)
  # @option input [Integer] :num_dice Number of dice to roll (alternative to dice_notation)
  # @option input [Integer] :num_sides Number of sides per die (alternative to dice_notation)
  # @option input [Integer] :modifier Optional modifier to add to the total
  # @option input [Boolean] :advantage Roll twice and take higher (d20 only)
  # @option input [Boolean] :disadvantage Roll twice and take lower (d20 only)
  # @option input [String] :description Optional description of the roll
  # @return [Hash] Result hash with :success, :rolls, :modifier, :total, :breakdown, etc.
  def self.roll(input)
    new(input).roll
  end

  def initialize(input)
    @input = input
    parse_input
  end

  def roll
    validate_parameters!

    # Handle advantage/disadvantage for d20 rolls
    if (@advantage || @disadvantage) && @num_dice == 1 && @num_sides == 20
      return roll_with_advantage_or_disadvantage
    end

    # Normal dice rolling
    rolls = Array.new(@num_dice) { rand(1..@num_sides) }
    sum = rolls.sum
    total = sum + @modifier

    {
      success: true,
      dice_notation: dice_notation_string,
      description: @description,
      rolls: rolls,
      modifier: @modifier,
      total: total,
      breakdown: build_breakdown(rolls, total)
    }
  end

  private

  def parse_input
    if @input.is_a?(String)
      parse_string_input
    elsif @input.is_a?(Hash)
      parse_hash_input
    else
      raise ArgumentError, "Input must be a String or Hash"
    end
  end

  def parse_string_input
    # Parse dice notation (e.g., "2d6+3", "1d20", "4d8-2")
    match = @input.match(/^(\d+)d(\d+)([+-]\d+)?$/i)

    unless match
      raise InvalidDiceNotation, "Invalid dice notation. Use format like '1d20', '2d6', '4d8+3'"
    end

    @num_dice = match[1].to_i
    @num_sides = match[2].to_i
    @modifier = match[3] ? match[3].to_i : 0
    @advantage = false
    @disadvantage = false
    @description = nil
    @original_notation = @input
  end

  def parse_hash_input
    if @input["dice_notation"] || @input[:dice_notation]
      notation = @input["dice_notation"] || @input[:dice_notation]
      match = notation.match(/^(\d+)d(\d+)([+-]\d+)?$/i)

      unless match
        raise InvalidDiceNotation, "Invalid dice notation. Use format like '1d20', '2d6', '4d8+3'"
      end

      @num_dice = match[1].to_i
      @num_sides = match[2].to_i
      @modifier = match[3] ? match[3].to_i : 0
      @original_notation = notation
    else
      @num_dice = (@input["num_dice"] || @input[:num_dice] || 1).to_i
      @num_sides = (@input["num_sides"] || @input[:num_sides]).to_i
      @modifier = (@input["modifier"] || @input[:modifier] || 0).to_i
      @original_notation = nil
    end

    @advantage = @input["advantage"] || @input[:advantage] || false
    @disadvantage = @input["disadvantage"] || @input[:disadvantage] || false
    @description = @input["description"] || @input[:description]
  end

  def validate_parameters!
    unless @num_sides
      raise InvalidDiceParameters, "Number of sides is required"
    end

    if @num_dice < 1 || @num_dice > 100
      raise InvalidDiceParameters, "Number of dice must be between 1 and 100"
    end

    if @num_sides < 2 || @num_sides > 1000
      raise InvalidDiceParameters, "Number of sides must be between 2 and 1000"
    end
  end

  def roll_with_advantage_or_disadvantage
    roll1 = rand(1..20)
    roll2 = rand(1..20)

    if @advantage
      base_roll = [roll1, roll2].max
      result = base_roll + @modifier
      {
        success: true,
        dice_notation: dice_notation_string,
        description: @description,
        rolls: [roll1, roll2],
        advantage: true,
        selected_roll: base_roll,
        modifier: @modifier,
        total: result,
        breakdown: "Rolled with advantage: [#{roll1}, #{roll2}], took #{base_roll}#{modifier_string} = #{result}"
      }
    else # disadvantage
      base_roll = [roll1, roll2].min
      result = base_roll + @modifier
      {
        success: true,
        dice_notation: dice_notation_string,
        description: @description,
        rolls: [roll1, roll2],
        disadvantage: true,
        selected_roll: base_roll,
        modifier: @modifier,
        total: result,
        breakdown: "Rolled with disadvantage: [#{roll1}, #{roll2}], took #{base_roll}#{modifier_string} = #{result}"
      }
    end
  end

  def dice_notation_string
    @original_notation || "#{@num_dice}d#{@num_sides}#{@modifier != 0 ? "#{@modifier > 0 ? '+' : ''}#{@modifier}" : ''}"
  end

  def modifier_string
    return '' if @modifier == 0
    " #{@modifier > 0 ? '+' : ''}#{@modifier}"
  end

  def build_breakdown(rolls, total)
    "Rolled #{@num_dice}d#{@num_sides}: [#{rolls.join(', ')}]#{modifier_string} = #{total}"
  end
end
