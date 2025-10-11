# Durable LLM Registry

This project maintains a comprehensive catalog of Large Language Models (LLMs) from various providers, providing structured documentation and metadata for each supported provider.

Note that this is a perpetual work-in-progress; its provided for convenience sake, but for guaranteed accuracy, consult the provider for authoritative information.

## Project Structure

The `catalog/` directory contains subdirectories for each LLM provider, organized as follows:

```
catalog/
├── provider-name/
│   ├── catalog.md          # Markdown documentation describing models and API
│   ├── openapi.yaml        # OpenAPI specification for the provider's REST API
│   └── models.jsonl        # Detailed metadata for available models (JSON Lines format)
```

## Providers

The following providers are currently cataloged:

- Anthropic
- Azure OpenAI
- Cohere
- Deepseek
- Google
- Groq
- Mistral AI
- OpenAI
- OpenCode Zen
- OpenRouter
- Perplexity
- Together
- xAI

## File Descriptions

### catalog.md
Each provider's `catalog.md` file contains:
- Overview of the provider and available models
- Detailed specifications for each model (context window, modalities, capabilities)
- Pricing information
- Usage examples
- Model selection guide

### openapi.yaml
OpenAPI 3.0 specification describing the provider's REST API endpoints, request/response schemas, and authentication requirements.

### models.jsonl
A JSON Lines file where each line is a JSON object containing detailed metadata for a single model, including:
- Model name and ID
- Family classification
- Context window size
- Maximum output tokens
- Supported input/output modalities
- Capabilities (e.g., function calling)
- Pricing information

## Usage

To update the catalogs with the latest model data from providers that support dynamic fetching, run:

```bash
ruby lib/updater.rb
```

This will fetch data from supported providers, update the feature matrix, and regenerate the catalog.md files for each provider.

## Contributing

When adding a new provider:
1. Create a subdirectory in `catalog/` with the provider name (lowercase, hyphens for spaces)
2. Add `catalog.md` with model documentation
3. Add `openapi.yaml` with the API specification
4. Add a processing script in `lib/providers/` if needed
5. Update this README

## License

CC0. Providers may hold intellectual property relating to their individual services, but you're free to use this compilation data free from any restriction on our side.


