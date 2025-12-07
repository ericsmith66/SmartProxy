# SmartProxy — Pluggable AI Proxy for NextGen Wealth Advisor

OpenAI-compatible proxy that routes between local Ollama (privacy-first) and Grok API (senior architect reasoning).

## Features
- Smart routing: privacy-sensitive queries → local Ollama
- Keyword overrides: #Hey Grok!, #Local, #70B, #405B
- Works with Continue.dev, OpenWebUI, agents
- Lightweight Ruby (Sinatra)

## Run
bundle install
rackup -p 11435   # or ruby ai_proxy.rb

Default: local Ollama
GROK_API_KEY=... AI_PROVIDER=grok rackup -p 11435  # Grok mode

## Privacy
Family data, portfolio, internship, paycheck, roth → always local Ollama
