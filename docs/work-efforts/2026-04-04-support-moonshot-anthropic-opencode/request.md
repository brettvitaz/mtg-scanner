# Request: Support Moonshot and Anthropic LLM Providers

**Date:** 2026-04-04
**Author:** brettvitaz

## Goal

Replace the legacy OpenAI-specific implementation with a unified, provider-agnostic interface supporting OpenAI, Moonshot (kimi-k2.5), and Anthropic (Claude) via HTTP. Update environment variables to be generic with no backwards compatibility.

## Requirements

1. Create unified LLM provider interface with support for OpenAI, Moonshot, and Anthropic
2. Implement HTTP-based providers for all three services (no SDK dependencies)
3. Support structured JSON output with Pydantic validation for all providers
4. Auto-downgrade response mode for Moonshot (json_schema → json_mode)
5. Remove legacy OpenAI-specific code (`openai_compat.py`)
6. Update environment variables to generic naming with provider-specific overrides
7. Add integration tests for all providers
8. Provide sensible defaults for each provider

## Scope

**In scope:**
- New `services/api/app/services/llm/` module with provider implementations
- Updated `settings.py` with new environment variable configuration
- Updated `recognizer.py` to use new provider factory
- Integration tests for all three providers
- Updated `.env.example` with new configuration format
- Documentation updates

**Out of scope:**
- OpenAI SDK or Anthropic SDK dependencies (using HTTP only)
- Streaming support
- Async/await conversion of existing code
- Changes to iOS app or other frontend components
- Changes to prompt files

## Verification

Run the following to verify:

```bash
# Run all API tests
make api-test

# Run integration tests for LLM providers
pytest services/api/tests/test_llm_providers.py -v

# Run linting
make api-lint

# Verify no legacy OpenAI-specific env vars remain
grep -r "OPENAI_API_KEY\|MTG_SCANNER_OPENAI" services/api/app/ || echo "No legacy references found"
```

## Context

Files or docs the agent should read before starting:

- `services/api/app/services/openai_compat.py` (legacy code to replace)
- `services/api/app/services/recognizer.py` (needs provider integration)
- `services/api/app/settings.py` (needs env var updates)
- `services/api/.env.example` (needs updates)
- `docs/work-efforts/CLAUDE.md` (work effort process)

## Notes

- Moonshot API is OpenAI-compatible at `https://api.moonshot.ai/v1`
- Anthropic uses different API format at `https://api.anthropic.com/v1` with Messages API
- For Anthropic structured output, use tool-based approach (recommended)
- Keep existing Pydantic models (`RecognitionResponse`, `RecognizedCard`)
- Default models: OpenAI=gpt-4.1-mini, Moonshot=kimi-k2.5, Anthropic=claude-sonnet-4-0
