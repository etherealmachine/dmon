// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "channels"
import { initializeToasts } from "components/Toast"

// Initialize toasts on page load and turbo navigation
document.addEventListener('turbo:load', initializeToasts)
document.addEventListener('DOMContentLoaded', initializeToasts)
