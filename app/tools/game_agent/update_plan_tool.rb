module GameAgentTools
  class UpdatePlanTool < RubyLLM::Tool
    description "Update the current plan with new items or mark items as completed. This helps track progress on multi-step tasks."

    def name
      "update_plan"
    end

    params do
      array :items, description: "Array of plan items (replaces the current plan)", required: true do
        object do
          string :description, description: "The plan item description", required: true
          boolean :completed, description: "Whether the item is completed", required: false
        end
      end
    end

    def initialize(game_agent)
      @game_agent = game_agent
    end

    def execute(items:)
      unless items.is_a?(Array)
        return {
          success: false,
          error: "Items must be an array"
        }
      end

      # Normalize items to ensure they have both description and completed fields
      plan_items = items.map do |item|
        {
          "description" => item["description"] || item[:description],
          "completed" => item["completed"] || item[:completed] || false
        }
      end

      @game_agent.plan = plan_items
      @game_agent.save!

      {
        success: true,
        message: "Plan updated successfully",
        plan: @game_agent.plan,
        count: @game_agent.plan.length
      }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
