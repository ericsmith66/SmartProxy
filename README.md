# SmartProxy — Pluggable AI Backend for NextGen Wealth Advisor

Lightweight Ruby (Sinatra) OpenAI-compatible proxy that intelligently routes between:
- **Local Ollama** (privacy-first, on-device — default for family data)
- **Grok API** (senior architect reasoning — on demand via "#Hey Grok!")

## Why This Exists
NextGen Wealth Advisor is a 100% private AI family-office tutor for high-net-worth heirs. All sensitive data (portfolio, trusts, internship paycheck, Roth balances, taxes, philanthropy) **must stay on-device**.

SmartProxy enables:
- Daily agent work and curriculum generation with local Ollama (70B/405B)
- Grok API for complex debugging, prompt engineering, and architecture when you say "#Hey Grok!"
- Single endpoint for OpenWebUI and Continue.dev

## Features
- Smart routing with privacy keywords (force local Ollama)
- Keyword override: `#Hey Grok!` → Grok API
- Full logging for debugging
- OpenAI-compatible — works with OpenWebUI, Continue.dev
- No sensitive data in repo

## Setup
1. `bundle install`
2. Create `.env`:
3. GROK_API_KEY=your_grok_key_here
4. rackup -p 11435 -o 0.0.0.0
### Remaining Proxy TODOs
1. **Streaming for Grok** — live typing (convert Grok chunks to proper SSE)
2. **Config file** — move keywords/routes to YAML (easier customization)
3. **Health check** — `/health` endpoint
4. **Cost tracking** — log Grok token usage
5. **Docker support** — containerize for easier deployment

The proxy is **stable and production-ready** in non-streaming mode — great for the Internship Edition launch.

Your call — push the README update and commit the current stable state?

SmartProxy preserved on GitHub — pluggable brain complete! 🚀