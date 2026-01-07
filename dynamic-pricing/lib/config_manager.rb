# Central configuration manager for application-specific configs
# Loads YAML/other configs at application boot and exposes a simple API.

require "yaml"
require "erb"

class ConfigManager
  class << self
    # Load all custom application configs
    def load!
      @configs = {}
      load_rate_retriever_config
      self
    end

    # Generic accessor
    def [](key)
      (@configs || {})[key.to_sym]
    end

    private

    def load_rate_retriever_config
      path = Rails.root.join("config", "rate_retriever.yml")
      return unless File.exist?(path)

      raw = YAML.load(ERB.new(File.read(path)).result) || {}
      env_config = raw[Rails.env] || {}
      # Use symbolized keys for easier access
      @configs[:rate_retriever] = deep_symbolize(env_config)
    end

    # Minimal deep symbolize to avoid pulling in extra dependencies
    def deep_symbolize(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = deep_symbolize(v)
        end
      when Array
        obj.map { |v| deep_symbolize(v) }
      else
        obj
      end
    end
  end
end
