# ai_proxy.rb — Smart AI Proxy for NextGen Wealth Advisor (Ollama stable + Grok non-streaming)
require 'sinatra'
require 'faraday'
require 'json'
require 'logger'
require 'fileutils'
require 'securerandom'

# Logging
FileUtils.mkdir_p("log")
log_file = File.open("log/proxy.log", "a")
log_file.sync = true
LOGGER = Logger.new(log_file)
LOGGER.level = Logger::INFO
LOGGER.formatter = proc { |severity, datetime, progname, msg| "[#{datetime}] #{severity} #{msg}\n" }

use Rack::CommonLogger, LOGGER

# Config constants
OLLAMA_URL = 'http://localhost:11434/api/chat'
GROK_URL = 'https://api.x.ai/v1/chat/completions'
GROK_API_KEY = ENV['GROK_API_KEY']

# Keyword overrides
OVERRIDE_LOCAL = ['#local', '#ollama', '#70b', '#405b']
OVERRIDE_GROK = ['#hey grok', '#heygrok', '#grok', '#architect']

# Privacy-sensitive keywords
PRIVACY_KEYWORDS = [
  'plaid', 'portfolio', 'internship', 'paycheck', 'roth', 'trust',
  'estate tax', 'family net worth', 'philanthropy', 'gusto', 'deductible'
]

# Architecture/debug keywords
ARCHITECTURE_KEYWORDS = ['prompt', 'agent', 'debug', 'rollback', 'workflow', 'architecture']

def route_provider(request_body)
  messages = request_body['messages'] || []
  user_message = messages.last ? messages.last['content'] : ''
  downcased = user_message.downcase.gsub(/[^a-z0-9#]/, '')

  requested_model = request_body['model'] || ''

  # Model selection override — if user picked grok-4-fast-reasoning, use Grok
  if requested_model.downcase.include?('grok')
    if GROK_API_KEY
      LOGGER.info "Model selection override: Grok (requested model '#{requested_model}')"
      return { provider: 'grok', model: 'grok-4-fast-reasoning' }
    else
      LOGGER.info "Grok model requested but key missing — fallback to Ollama"
    end
  end

  # Keyword override
  if OVERRIDE_GROK.any? { |k| downcased.include?(k.tr('#', '').downcase) } || downcased.include?('heygrok')
    if GROK_API_KEY
      LOGGER.info "Override: Grok (keyword in '#{user_message}')"
      return { provider: 'grok', model: 'grok-4-fast-reasoning' }
    else
      LOGGER.info "Grok override requested but key missing — fallback to Ollama"
    end
  end

  # Local override
  if OVERRIDE_LOCAL.any? { |k| downcased.include?(k.tr('#', '').downcase) }
    model = downcased.include?('405b') ? 'llama3.1:405b' : 'llama3.1:70b'
    LOGGER.info "Override: Ollama #{model} (keyword in '#{user_message}')"
    return { provider: 'ollama', model: model }
  end

  # Privacy-sensitive → force local
  if PRIVACY_KEYWORDS.any? { |k| downcased.include?(k) }
    LOGGER.info "Privacy route: local Ollama 70B"
    return { provider: 'ollama', model: 'llama3.1:70b' }
  end

  # Architecture/debug → Grok
  if ARCHITECTURE_KEYWORDS.any? { |k| downcased.include?(k) }
    if GROK_API_KEY
      LOGGER.info "Architecture route: Grok"
      return { provider: 'grok', model: 'grok-4-fast-reasoning' }
    end
  end

  # Default
  LOGGER.info "Default: local Ollama 70B"
  { provider: 'ollama', model: 'llama3.1:70b' }
end

set :port, 11435

# CORS + OPTIONS
before do
  headers['Access-Control-Allow-Origin'] = '*'
  headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
end

options '*' do
  status 200
  ''
end

post '/v1/chat/completions' do
  request_body = JSON.parse(request.body.read)
  route = route_provider(request_body)

  # Force model override for Grok
  if route[:provider] == 'grok'
    request_body['model'] = route[:model]
  else
    request_body['model'] ||= route[:model]
  end

  # Force non-streaming for both Ollama and Grok — stable single JSON response

  user_agent = request.env['HTTP_USER_AGENT'] || ''
  is_continue_jetbrains = user_agent.downcase.include?('Js/JS 5.23.2') || user_agent.downcase.include?('jetbrains')

  request_body['stream'] = false
  if user_agent == 'Js/JS 5.23.2' then request_body['stream'] = true end

  LOGGER.info "Streaming: #{request_body['stream']}"
  LOGGER.info "User-Agent: #{user_agent}"
  LOGGER.info "Routing to #{route[:provider]} (model: #{request_body['model']})"
  LOGGER.info "FULL REQUEST BODY: #{request_body.to_json}"

  case route[:provider]
  when 'ollama'
    LOGGER.info "Sending to Ollama: #{request_body['model']} (messages: #{request_body['messages'].size})"
    response = Faraday.post(OLLAMA_URL, request_body.to_json, "Content-Type" => "application/json")
    ollama_body = response.body || ""

    if response.status == 200
      begin
        ollama_json = JSON.parse(ollama_body)
        content = ollama_json["message"]["content"] || ""

        openai_response = {
          "id": "chatcmpl-#{SecureRandom.hex(4)}",
          "object": "chat.completion",
          "created": Time.now.to_i,
          "model": request_body['model'],
          "choices": [
            {
              "index": 0,
              "message": {
                "role": "assistant",
                "content": content
              },
              "finish_reason": ollama_json["done"] ? "stop" : nil
            }
          ],
          "usage": {
            "prompt_tokens": ollama_json["prompt_eval_count"] || 0,
            "completion_tokens": ollama_json["eval_count"] || 0,
            "total_tokens": (ollama_json["prompt_eval_count"] || 0) + (ollama_json["eval_count"] || 0)
          }
        }

        body = openai_response.to_json
        LOGGER.info "Converted Ollama to OpenAI format | body size: #{body.bytesize}"
      rescue JSON::ParserError => e
        LOGGER.error "Failed to parse Ollama response: #{e.message}"
        body = ollama_body
      end
    else
      body = ollama_body
    end

  when 'grok'
    LOGGER.info "Sending to Grok (grok-4-fast-reasoning)"
    LOGGER.info "GROK REQUEST BODY: #{request_body.to_json}"
    conn = Faraday.new(url: 'https://api.x.ai') do |f|
      f.headers['Authorization'] = "Bearer #{GROK_API_KEY}"
      f.headers['Content-Type'] = 'application/json'
    end
    response = conn.post('/v1/chat/completions', request_body.to_json)
    body = response.body || ""
    LOGGER.info "Grok response status: #{response.status} | body size: #{body.bytesize}"
    LOGGER.info "GROK FULL RESPONSE BODY: #{body}"
    if response.status != 200
      LOGGER.error "Grok error: #{body}"
    end
  end

  status response.status
  content_type 'application/json'
  body
end

# Test route — front page
get '/v1' do
  "SmartProxy for NextGen Wealth Advisor — OpenAI-compatible endpoint<br><br>
  Provider: #{GROK_API_KEY ? 'Grok ready' : 'Local Ollama'}<br>
  Routing: privacy-sensitive → local Ollama | #Hey Grok! → Grok | default → Ollama 70B<br>
  <a href='/v1/models'>List models</a> | <a href='/v1/openapi.json'>OpenAPI spec</a>"
end

# Model list
get '/v1/models' do
  content_type :json
  data = [
    { "id": "llama3.1:70b", "object": "model", "created": Time.now.to_i, "owned_by": "ollama" },
    { "id": "llama3.1:405b", "object": "model", "created": Time.now.to_i, "owned_by": "ollama" }
  ]
  data << { "id": "grok-4-fast-reasoning", "object": "model", "created": Time.now.to_i, "owned_by": "grok" } if GROK_API_KEY
  {
    "object": "list",
    "data": data
  }.to_json
end

# OpenAPI spec
get '/v1/openapi.json' do
  content_type :json
  {
    "openapi": "3.1.0",
    "info": { "title": "SmartProxy for NextGen Wealth Advisor", "version": "1.0.0" },
    "servers": [ { "url": "http://localhost:11435/v1" } ],
    "paths": {
      "/chat/completions": { "post": { "operationId": "chatCompletion" } },
      "/models": { "get": { "operationId": "listModels" } }
    }
  }.to_json
end

puts "SmartProxy running on http://localhost:11435"
puts "Privacy keywords → local Ollama | #Hey Grok! → Grok | default → Ollama 70B"