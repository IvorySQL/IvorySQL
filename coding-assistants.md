# AI Coding Assistants

This document provides guidance for AI tools and developers using AI assistance when contributing to IvorySQL.

AI tools helping with IvorySQL development should follow the standard development process:

- `CONTRIBUTING.md` - Contribution guidelines and workflow
- PostgreSQL coding conventions
- Existing IvorySQL code patterns and architecture

## Licensing and Legal Requirements

All contributions must comply with IvorySQL's licensing requirements:

- IvorySQL is released under the Apache License, Version 2.0
- See `LICENSE` file for the complete license text
- All code must be compatible with the Apache 2.0 license

If the contribution you're submitting is original work, it will be released as part of IvorySQL under the Apache License 2.0.

If the contribution you're submitting is NOT original work:
- You must indicate the name of the license
- The license must be compatible with Apache License 2.0
- Proper attribution must be provided to the original source
- Never remove licensing headers from existing code

## Human Responsibility

AI agents cannot take legal responsibility for contributions. The human submitter is responsible for:

- Reviewing all AI-generated code
- Ensuring compliance with licensing requirements
- Taking full responsibility for the contribution

## Attribution

When AI tools contribute to IvorySQL development, proper attribution helps track the evolving role of AI in the development process. Contributions should include an `Assisted-by` tag in the following format:

```
Assisted-by: AGENT_NAME:MODEL_VERSION
```

Where:

- `AGENT_NAME` is the name of the AI tool or framework
- `MODEL_VERSION` is the specific model version used

Examples:

```
Assisted-by: Claude:4.6
Assisted-by: GitHub:Copilot
Assisted-by: OpenAI:gpt-4
```
