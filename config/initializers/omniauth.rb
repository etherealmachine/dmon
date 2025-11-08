# frozen_string_literal: true

# OmniAuth configuration for Rails 8
# This is required for OmniAuth 2.x to work properly

OmniAuth.config.allowed_request_methods = [:get, :post]

# In production, you should set this to true and only allow specific origins
OmniAuth.config.silence_get_warning = true

# Handle test mode if needed
OmniAuth.config.test_mode = false if Rails.env.production?

# Log OmniAuth info for debugging
Rails.logger.info "OmniAuth configured with providers: #{Devise.omniauth_providers.inspect}"
