require 'net/http'
require 'uri'

module Helpers
  class CircuitBreaker
    # In-memory process-local circuit breaker with background probing.
    # Use CircuitBreaker.for(...) to get a singleton instance per name.

    DEFAULT_THRESHOLD = 5
    DEFAULT_OPEN_TTL = 60
    DEFAULT_PROBE_INTERVAL = 10

    @@instances = {}
    @@mutex = Mutex.new

    def self.for(name:, threshold: nil, open_ttl: nil, probe_url: nil, probe_interval: nil)
      @@mutex.synchronize do
        return @@instances[name.to_s] if @@instances.key?(name.to_s)
        inst = new(name: name.to_s, threshold: threshold, open_ttl: open_ttl, probe_url: probe_url, probe_interval: probe_interval)
        @@instances[name.to_s] = inst
        inst
      end
    end

    def initialize(name:, threshold: nil, open_ttl: nil, probe_url: nil, probe_interval: nil)
      @name = name.to_s
      @threshold = (threshold || DEFAULT_THRESHOLD).to_i
      @open_ttl = (open_ttl || DEFAULT_OPEN_TTL).to_i
      @probe_url = probe_url
      @probe_interval = (probe_interval || DEFAULT_PROBE_INTERVAL).to_i

      @mutex = Mutex.new
      @state = 'closed'
      @fails = 0
      @opened_at = nil
      @probe_thread = nil
    end

    def allow?
      @mutex.synchronize do
        @state == 'closed' || @state == 'half_open'
      end
    end

    def record_success
      @mutex.synchronize do
        @fails = 0
        @state = 'closed'
        stop_probe_thread
      end
    end

    def record_failure
      to_start_probe = false
      @mutex.synchronize do
        @fails += 1
        if @fails >= @threshold && @state != 'open'
          @state = 'open'
          @opened_at = Time.now
          to_start_probe = true
        end
      end
      start_probe_thread if to_start_probe
    end

    def reset
      @mutex.synchronize do
        @fails = 0
        @state = 'closed'
        @opened_at = nil
        stop_probe_thread
      end
    end

    def open?
      @mutex.synchronize { @state == 'open' }
    end

    private

    def start_probe_thread
      return if @probe_url.nil?
      return if @probe_thread && @probe_thread.alive?

      @probe_thread = Thread.new do
        loop do
          sleep @probe_interval
          begin
            success = probe_upstream
            if success
              record_success
              break
            else
              # keep trying
            end
          rescue StandardError
            # ignore and continue
          end
        end
      end
    end

    def stop_probe_thread
      if @probe_thread && @probe_thread.alive?
        Thread.kill(@probe_thread) rescue nil
        @probe_thread = nil
      end
    end

    def probe_upstream
      return false if @probe_url.nil? || @probe_url.empty?
      uri = URI(@probe_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5
      path = uri.path && !uri.path.empty? ? uri.path : '/'
      req = Net::HTTP::Get.new(path)
      res = http.request(req)
      res && res.code.to_i < 500
    rescue StandardError
      false
    end
  end
end
