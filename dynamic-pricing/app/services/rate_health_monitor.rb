require_relative 'helpers/rate_health_monitor'

# Backwards-compatibility shim: keep `RateHealthMonitor` constant at top-level
RateHealthMonitor = Helpers::RateHealthMonitor
