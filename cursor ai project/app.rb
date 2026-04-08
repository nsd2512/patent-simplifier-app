require "sinatra"
require "json"
require "securerandom"

require_relative "lib/patent_assistant"
require_relative "lib/rate_limiter"
require_relative "lib/usage_monitor"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", "4567").to_i

configure do
  set :public_folder, File.join(__dir__, "public")
  set :views, File.join(__dir__, "views")
  set :static, true
end

DEFAULT_LIMITER = RateLimiter.build_default
GENERATE_LIMITER = RateLimiter::FixedWindow.new(
  max: ENV.fetch("GENERATE_RATE_LIMIT_MAX", ENV.fetch("RATE_LIMIT_MAX", "20")).to_i,
  window_seconds: ENV.fetch("GENERATE_RATE_LIMIT_WINDOW_SECONDS", ENV.fetch("RATE_LIMIT_WINDOW_SECONDS", "60")).to_i
)

USAGE_MUTEX = Mutex.new
USAGE_STORE = {
  total: 0,
  by_path: Hash.new(0),
  by_ip: Hash.new(0)
}

helpers do
  def json_params
    payload = request.body.read
    return {} if payload.nil? || payload.strip.empty?
    JSON.parse(payload)
  rescue JSON::ParserError
    {}
  end

  def respond_json(status_code, obj)
    content_type :json
    status status_code
    obj.to_json
  end
end

before "/api/*" do
  @request_id = SecureRandom.uuid
  @request_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  if request.path_info == "/api/health"
    next
  end

  limiter = (request.path_info == "/api/generate") ? GENERATE_LIMITER : DEFAULT_LIMITER
  client_key = "#{request.ip}:#{request.path_info}"

  unless limiter.allow?(client_key)
    headers "Retry-After" => limiter.window_seconds.to_s
    respond_json(429, {
      "error" => "rate_limited",
      "message" => "Too many requests. Please slow down and try again.",
      "requestId" => @request_id,
      "limit" => limiter.max,
      "windowSeconds" => limiter.window_seconds
    })
    halt
  end
end

after "/api/*" do
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - (@request_start_time || 0)) * 1000.0)

  USAGE_MUTEX.synchronize do
    USAGE_STORE[:total] += 1
    USAGE_STORE[:by_path][request.path_info] += 1
    USAGE_STORE[:by_ip][request.ip] += 1
  end

  UsageMonitor.log_request(
    io: $stdout,
    request: request,
    status: response.status,
    duration_ms: duration_ms,
    extra: { requestId: @request_id }
  )
end

get "/" do
  erb :index
end

post "/api/assess" do
  data = json_params
  result = PatentAssistant.assess_idea(data)
  respond_json(200, result)
end

post "/api/draft" do
  data = json_params
  result = PatentAssistant.generate_draft(data)
  respond_json(200, result)
end

post "/api/search" do
  data = json_params
  result = PatentAssistant.search_prior_art(data)
  respond_json(200, result)
end

get "/api/health" do
  respond_json(200, { "ok" => true })
end

get "/api/usage" do
  unless ENV["ENABLE_USAGE_ENDPOINT"].to_s == "1"
    respond_json(403, { "error" => "usage_endpoint_disabled" })
  end

  snapshot = nil
  USAGE_MUTEX.synchronize do
    snapshot = {
      total: USAGE_STORE[:total],
      byPath: USAGE_STORE[:by_path].to_a.sort_by { |(_, v)| -v }.take(20),
      byIp: USAGE_STORE[:by_ip].to_a.sort_by { |(_, v)| -v }.take(20)
    }
  end

  respond_json(200, snapshot)
end

post "/api/generate" do
  data = json_params

  begin
    assess = PatentAssistant.assess_idea(data)
    draft = PatentAssistant.generate_draft(data)
    search = PatentAssistant.search_prior_art(draft["search_payload"] || data)
    respond_json(200, { "assessment" => assess, "draft" => draft, "search" => search })
  rescue => e
    respond_json(500, { "error" => e.message })
  end
end

