class AiService
  class Error < StandardError
    attr_reader :original_error, :response_body, :provider

    def initialize(message, original_error: nil, response_body: nil, provider: nil)
      super(message)
      @original_error = original_error
      @response_body = response_body
      @provider = provider
    end

    def detailed_message
      parts = [message]
      parts << "Provider: #{provider}" if provider.present?
      parts << "Response body: #{response_body}" if response_body.present?
      parts << "Original error: #{original_error.class} - #{original_error.message}" if original_error
      parts.join("\n")
    end
  end

  # Canonical registry of allowed models and their providers
  MODELS = {
    # OpenAI models
    "gpt-4o" => :openai,
    "gpt-4o-mini" => :openai,
    "gpt-5" => :openai,
    "gpt-5-nano" => :openai,

    # Claude models
    "claude-3-5-sonnet-20241022" => :claude,
    "claude-3-5-haiku-20241022" => :claude,
    "claude-haiku-4-5-20251001" => :claude,
    "claude-opus-4-5-20250514" => :claude,
  }.freeze

  # Get provider for a given model
  # @param model [String] The model name
  # @return [Symbol] The provider symbol (:openai or :claude)
  # @raises [ArgumentError] If model is not in the registry
  def self.provider_for(model)
    provider = MODELS[model]
    raise ArgumentError, "Unknown model: #{model}. Allowed models: #{MODELS.keys.join(', ')}" unless provider
    provider
  end

  # Get all allowed models
  # @return [Array<String>] List of allowed model names
  def self.allowed_models
    MODELS.keys
  end

  # Get all models for a specific provider
  # @param provider [Symbol] The provider (:openai or :claude)
  # @return [Array<String>] List of model names for that provider
  def self.models_for_provider(provider)
    MODELS.select { |_, p| p == provider }.keys
  end

  # Check if a model is valid
  # @param model [String] The model name
  # @return [Boolean] True if model exists in registry
  def self.valid_model?(model)
    MODELS.key?(model)
  end

  # Create a service instance for the given model
  # @param model [String] The model name
  # @param api_key [String, nil] Optional API key (uses ENV if not provided)
  # @return [OpenAiService, ClaudeService] The appropriate service instance
  # @raises [ArgumentError] If model is not in the registry
  def self.create(model:, api_key: nil)
    provider = provider_for(model)

    case provider
    when :openai
      OpenAiService.new(api_key: api_key, model: model)
    when :claude
      ClaudeService.new(api_key: api_key, model: model)
    else
      raise ArgumentError, "Unknown provider: #{provider}"
    end
  rescue OpenAiService::Error, ClaudeService::Error => e
    # Wrap provider-specific errors in our unified error
    raise Error.new(
      e.message,
      original_error: e.original_error,
      response_body: e.response_body,
      provider: provider
    )
  end

  # Unified chat interface that automatically selects the right provider
  # @param model [String] The model name
  # @param messages [Array<Hash>] Array of message hashes with :role and :content
  # @param system_message [String, nil] Optional system message
  # @param tools [Array<Hash>] Array of tool definitions
  # @param stream [Boolean] Whether to stream the response
  # @param api_key [String, nil] Optional API key
  # @return [Hash] Unified response with :content, :tool_calls, etc.
  def self.chat(model:, messages:, system_message: nil, tools: [], stream: false, api_key: nil, &block)
    service = create(model: model, api_key: api_key)
    provider = provider_for(model)

    service.chat(
      messages: messages,
      system_message: system_message,
      tools: tools,
      stream: stream,
      &block
    )
  rescue OpenAiService::Error, ClaudeService::Error => e
    # Wrap provider-specific errors in our unified error
    raise Error.new(
      e.message,
      original_error: e.original_error,
      response_body: e.response_body,
      provider: provider
    )
  end
end
