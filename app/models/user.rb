# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  last_sign_in_at        :datetime
#  name                   :string           not null
#  provider               :string           default("google_oauth2"), not null
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  uid                    :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_provider_and_uid      (provider,uid) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class User < ApplicationRecord
  # Include devise modules for OAuth only
  devise :omniauthable, omniauth_providers: [:google_oauth2]

  has_many :adventures, dependent: :destroy
  has_many :games, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :provider, presence: true
  validates :uid, presence: true

  def self.from_omniauth(auth)
    # Find existing user by provider/uid or email
    user = where(provider: auth.provider, uid: auth.uid).first ||
           where(email: auth.info.email).first

    if user
      # Update the user's info from OAuth data
      user.update!(
        name: auth.info.name,
        provider: auth.provider,
        uid: auth.uid
      )
    else
      # Create new user from OAuth data
      user = create!(
        email: auth.info.email,
        name: auth.info.name,
        provider: auth.provider,
        uid: auth.uid
      )
    end

    user
  end

  def preferred_model=(model)
    raise "Model must be a valid AI model" unless AiService.valid_model?(model)
    Rails.cache.write("user:#{id}:preferred_model", model, expires_in: 1.days)
  end

  def preferred_model
    Rails.cache.read("user:#{id}:preferred_model") || "gpt-5-nano"
  end

  # Track token usage for a specific model
  # @param model [String] The model name
  # @param input_tokens [Integer] Number of input tokens used
  # @param output_tokens [Integer] Number of output tokens generated
  def track_token_usage(model:, input_tokens: 0, output_tokens: 0)
    return unless AiService.valid_model?(model)

    # Increment input tokens
    if input_tokens > 0
      input_key = cache_key_for_tokens(model, :input)
      current_input = Rails.cache.read(input_key) || 0
      Rails.cache.write(input_key, current_input + input_tokens, expires_in: 30.days)
    end

    # Increment output tokens
    if output_tokens > 0
      output_key = cache_key_for_tokens(model, :output)
      current_output = Rails.cache.read(output_key) || 0
      Rails.cache.write(output_key, current_output + output_tokens, expires_in: 30.days)
    end
  end

  # Get token usage for a specific model
  # @param model [String] The model name
  # @return [Hash] Hash with :input and :output token counts
  def token_usage_for_model(model)
    {
      input: Rails.cache.read(cache_key_for_tokens(model, :input)) || 0,
      output: Rails.cache.read(cache_key_for_tokens(model, :output)) || 0
    }
  end

  # Get token usage for all models
  # @return [Hash] Hash keyed by model name with :input and :output counts
  def token_usage
    usage = {}
    AiService.allowed_models.each do |model|
      model_usage = token_usage_for_model(model)
      # Only include models that have been used
      if model_usage[:input] > 0 || model_usage[:output] > 0
        usage[model] = model_usage
      end
    end
    usage
  end

  private

  def cache_key_for_tokens(model, type)
    "user:#{id}:token_usage:#{model}:#{type}"
  end

end
