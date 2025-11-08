class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    user = User.from_omniauth(request.env["omniauth.auth"])

    if user.persisted?
      user.update(last_sign_in_at: Time.current)
      sign_in(user, event: :authentication)

      # Redirect back to where the user was trying to go, or root if none stored
      redirect_to stored_location_for(:user) || root_path, notice: "Successfully signed in with Google!"
    else
      redirect_to root_path, alert: "Failed to create or sign in user account."
    end
  end

  def failure
    redirect_to root_path, alert: "Authentication failed."
  end
end
