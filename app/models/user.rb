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
    Rails.cache.write("user:#{id}:preferred_model", model, expires_in: 1.days)
  end

  def preferred_model
    Rails.cache.read("user:#{id}:preferred_model") || "gpt-4o-mini"
  end

end
