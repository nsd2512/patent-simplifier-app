module RateLimiter
  # Simple in-memory fixed-window rate limiting.
  #
  # Notes:
  # - Works best for single-instance deployments (free tiers typically do).
  # - For multi-instance scaling, switch to Redis-backed rate limiting.
  class FixedWindow
    attr_reader :max, :window_seconds

    def initialize(max:, window_seconds:, ttl_prune_seconds: nil)
      @max = max
      @window_seconds = window_seconds
      @ttl_prune_seconds = ttl_prune_seconds || window_seconds * 2
      @buckets = {}
      @mutex = Mutex.new
    end

    def allow?(key)
      now = Time.now.to_f
      bucket = nil

      @mutex.synchronize do
        # Prune old buckets to avoid unbounded memory growth.
        @buckets.delete_if { |_k, v| (now - v[:window_start]) > @ttl_prune_seconds }

        bucket = @buckets[key]
        if bucket.nil? || (now - bucket[:window_start]) >= @window_seconds
          bucket = { window_start: now, count: 0 }
          @buckets[key] = bucket
        end

        bucket[:count] += 1
        allowed = bucket[:count] <= @max
        return allowed
      end
    end
  end

  def self.build_default
    # Defaults chosen to be "developer friendly" but still protect the service.
    # Override via env vars for tuning.
    max = ENV.fetch("RATE_LIMIT_MAX", "60").to_i
    window_seconds = ENV.fetch("RATE_LIMIT_WINDOW_SECONDS", "60").to_i

    FixedWindow.new(max: max, window_seconds: window_seconds)
  end
end

