require 'net/http'
require 'uri'

module Helpers
  class RateHealthMonitor
    class << self
      def start_async
        Thread.new { start }
      end

      def start
        Rails.logger.info("Starting RateHealthMonitor")
        @last_seen_healthy = nil

        loop do
          begin
            healthy = check_upstream

            # If we observed a transition from unhealthy -> healthy, trigger immediate batch
            if @last_seen_healthy == false && healthy == true
              Rails.logger.info("Upstream recovered; evaluating whether to trigger immediate rate batch run")
              begin
                unless RedisService.rates_fresh?
                  Rails.logger.info("Rates not fresh in Redis — triggering immediate rate batch run")
                  PricingBatchService.call
                else
                  Rails.logger.info("Rates already fresh in Redis — skipping immediate batch")
                end
              rescue StandardError => e
                Rails.logger.error("Failed to run immediate rate batch: #{e.class} #{e.message}")
              end
            end

            @last_seen_healthy = healthy
          rescue StandardError => e
            Rails.logger.error("RateHealthMonitor error: #{e.class} #{e.message}")
          end

          interval = if Rails.application.config.respond_to?(:upstream_health_check) &&
                        Rails.application.config.upstream_health_check[:check_interval_seconds]
                     Rails.application.config.upstream_health_check[:check_interval_seconds]
                   else
                     30
                   end
          sleep interval
        end
      end

      private

      def check_upstream
        host = Rails.application.config.rate_api && Rails.application.config.rate_api[:host]
        return false if host.nil? || host.empty?

        uri = URI(host)

        # Use GET to check service health; fall back to TCP failure as unhealthy
        timeout = if Rails.application.config.respond_to?(:upstream_health_check) &&
                      Rails.application.config.upstream_health_check[:check_timeout_seconds]
                    Rails.application.config.upstream_health_check[:check_timeout_seconds]
                  else
                    5
                  end

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = timeout
        http.read_timeout = timeout

        # Allow overriding the health-check path via config
        configured_path = if Rails.application.config.respond_to?(:upstream_health_check)
                            Rails.application.config.upstream_health_check[:path]
                          end

        path = if configured_path && !configured_path.to_s.empty?
                 configured_path
               else
                 uri.path && !uri.path.empty? ? uri.path : '/'
               end
        request = Net::HTTP::Get.new(path)
        token = Rails.application.config.rate_api[:token]
        request['token'] = token if token && !token.to_s.empty?

        response = http.request(request)
        # Treat any non-5xx response as "up" (server reachable). APIs that only accept POST
        # may return 405 for GET; that's still evidence the upstream process is running.
        healthy = response && response.code.to_i < 500
        Rails.logger.debug("RateHealthMonitor: upstream #{uri.host} healthy=#{healthy} (code=#{response&.code})")
        healthy
      rescue StandardError => e
        Rails.logger.warn("RateHealthMonitor: upstream check failed: #{e.class} #{e.message}")
        false
      end
    end
  end
end
