require_relative 'helpers/circuit_breaker'

# Backwards-compatibility shim: keep `CircuitBreaker` constant at top-level
CircuitBreaker = Helpers::CircuitBreaker
