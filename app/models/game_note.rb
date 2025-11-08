# == Schema Information
#
# Table name: game_notes
#
#  id         :bigint           not null, primary key
#  actions    :jsonb
#  content    :text
#  history    :jsonb
#  note_type  :string
#  stats      :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  game_id    :bigint           not null
#
# Indexes
#
#  index_game_notes_on_game_id  (game_id)
#
# Foreign Keys
#
#  fk_rails_...  (game_id => games.id)
#
class GameNote < ApplicationRecord
  belongs_to :game

  validates :game, presence: true
  validates :note_type, presence: true

  # Scope for getting notes in chronological order
  scope :chronological, -> { order(created_at: :asc) }
  scope :by_type, ->(type) { where(note_type: type) }

  def self.note_types
    [
      ['Note', 'note'],
      ['NPC', 'npc'],
      ['Item', 'item'],
      ['Context', 'context'],
    ]
  end

  # Call an action by index
  # @param index [Integer] The index of the action to call
  # @return [Hash] The result of the action
  def call_action(index)
    return { success: false, error: "No actions defined" } if actions.blank?
    return { success: false, error: "Action index out of range" } if index >= actions.length || index < 0

    action = actions[index]
    action_type = action['type'] || action[:type]

    return { success: false, error: "Action type not specified" } if action_type.blank?

    method_name = "#{action_type}_action"

    unless respond_to?(method_name, true)
      return { success: false, error: "Unknown action type: #{action_type}" }
    end

    result = send(method_name, action)

    # Append result to history
    append_to_history(result)

    result
  end

  private

  # Roll dice action
  # @param action [Hash] The action definition with roll parameters
  # @return [Hash] The roll result
  def roll_action(action)
    args = action['args'] || action[:args] || {}

    begin
      roll_result = RollService.roll(args)

      {
        success: true,
        action_type: 'roll',
        action_name: action['name'] || action[:name],
        action_description: action['description'] || action[:description],
        result: roll_result,
        timestamp: Time.current
      }
    rescue RollService::InvalidDiceNotation, RollService::InvalidDiceParameters => e
      {
        success: false,
        action_type: 'roll',
        action_name: action['name'] || action[:name],
        error: e.message,
        timestamp: Time.current
      }
    end
  end

  # Append an action result to the history
  def append_to_history(result)
    self.history ||= []
    self.history << result
    save
  end
end
