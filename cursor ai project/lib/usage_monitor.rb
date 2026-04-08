require "json"

module UsageMonitor
  def self.bump!(store, key, amount = 1)
    store[key] ||= 0
    store[key] += amount
  end

  def self.log_request(io:, request:, status:, duration_ms:, extra: {})
    payload = {
      ts: Time.now.utc.iso8601,
      method: request.request_method,
      path: request.path_info,
      status: status,
      duration_ms: duration_ms.round(1),
      ip: (request.get_header("HTTP_X_FORWARDED_FOR") || request.ip).to_s.split(",").first.strip,
      ua: request.user_agent.to_s,
      extra: extra || {}
    }

    io.puts(payload.to_json)
    io.flush if io.respond_to?(:flush)
  end
end

