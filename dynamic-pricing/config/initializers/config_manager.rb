# Load all central application configuration at boot
require Rails.root.join("lib", "config_manager")

ConfigManager.load!
