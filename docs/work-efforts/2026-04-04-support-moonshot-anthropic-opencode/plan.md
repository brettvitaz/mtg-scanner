# Plan: Support Moonshot and Anthropic LLM Providers

**Planned by:** opencode
**Date:** 2026-04-04

## Approach

I will create a new unified LLM provider system under `services/api/app/services/llm/` with separate provider implementations for OpenAI, Moonshot, and Anthropic. Each provider will implement a common `LLMProvider` protocol and handle HTTP requests/responses according to the provider's API specification. The existing `recognizer.py` will be updated to use a factory function that creates the appropriate provider based on configuration. All environment variables will be updated to use generic naming with provider-specific overrides available.

## Implementation Steps

1. **Create base module structure**
   - Create `services/api/app/services/llm/__init__.py`
   - Create `services/api/app/services/llm/base.py` with LLMProvider protocol and shared utilities

2. **Implement OpenAI provider (updated from legacy)**
   - Create `services/api/app/services/llm/openai_provider.py`
   - Support json_schema, json_mode, and raw response modes
   - Use modern OpenAI API format

3. **Implement Moonshot provider**
   - Create `services/api/app/services/llm/moonshot_provider.py`
   - OpenAI-compatible implementation
   - Auto-downgrade json_schema to json_mode with warning

4. **Implement Anthropic provider**
   - Create `services/api/app/services/llm/anthropic_provider.py`
   - Use Messages API with tool-based structured output
   - Handle Anthropic-specific content block format

5. **Update settings.py**
   - Add new generic LLM environment variables
   - Add provider-specific override variables
   - Remove legacy OpenAI-specific settings

6. **Update recognizer.py**
   - Remove OpenAIRecognitionProvider class
   - Remove openai_compat imports
   - Integrate new LLM provider factory

7. **Update .env.example**
   - Replace legacy OpenAI vars with new generic format
   - Add examples for all three providers

8. **Create integration tests**
   - Create `services/api/tests/test_llm_providers.py`
   - Test each provider with mocked HTTP responses
   - Test provider factory
   - Test JSON extraction utilities

9. **Delete legacy code**
   - Remove `services/api/app/services/openai_compat.py`

10. **Run verification**
    - Run all tests
    - Run linting
    - Verify no legacy references remain

Dependencies:
- Step 2, 3, 4 depend on Step 1
- Step 5 can run in parallel with Steps 2-4
- Step 6 depends on Steps 2-4 and 5
- Step 8 depends on Steps 2-4
- Steps 9 and 10 depend on all previous steps

## Files to Modify

| File | Change |
|------|--------|
| `services/api/app/services/llm/__init__.py` | Create - exports and factory function |
| `services/api/app/services/llm/base.py` | Create - LLMProvider protocol, shared utilities |
| `services/api/app/services/llm/openai_provider.py` | Create - OpenAI HTTP provider |
| `services/api/app/services/llm/moonshot_provider.py` | Create - Moonshot HTTP provider |
| `services/api/app/services/llm/anthropic_provider.py` | Create - Anthropic HTTP provider |
| `services/api/app/settings.py` | Update - new env vars, remove legacy |
| `services/api/app/services/recognizer.py` | Update - use new providers, remove old code |
| `services/api/.env.example` | Update - new configuration format |
| `services/api/tests/test_llm_providers.py` | Create - integration tests |
| `services/api/app/services/openai_compat.py` | Delete - legacy code |

## Risks and Open Questions

- **Risk:** Anthropic tool-based structured output may have different behavior than OpenAI's json_schema. Will implement and test carefully.
- **Risk:** Moonshot auto-downgrade from json_schema to json_mode may cause confusion. Will add clear warning log.
- **Assumption:** All providers support base64 image encoding. Verified for all three.
- **Assumption:** Existing Pydantic models (`RecognitionResponse`, `RecognizedCard`) will work with all provider outputs. Will validate in tests.

## Verification Plan

```bash
# Run all API tests
make api-test

# Run specific integration tests
pytest services/api/tests/test_llm_providers.py -v

# Run linting
make api-lint

# Verify no legacy references
grep -r "OPENAI_API_KEY\|MTG_SCANNER_OPENAI" services/api/app/ || echo "No legacy references found"

# Test provider factory directly
python -c "from app.services.llm import get_llm_provider; from app.settings import get_settings; p = get_llm_provider(get_settings()); print(f'Provider: {p.provider_name}')"
```
