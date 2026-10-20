# Repository Markdown Style Guide

A practical set of rules for formatting Markdown files in the repository. Focused on readability, consistent style, and simple navigation without extraneous decorative markup.

## 1. General Rules

- Follow CommonMark and GitHub Flavored Markdown specifications.
- Maintain one distinct topic or scope per file.
- Do not duplicate information already documented elsewhere.
- Write concisely and concretely.
- Maintain a clean heading hierarchy.
- Do not use emojis or decorative symbols.
- Avoid large walls of text without sectional division.
- Avoid raw HTML when standard Markdown syntax suffices.
- Do not include rapidly changing state without citing a source or verification mechanism.

---

## 2. Document Structure

Every document must present an intuitive hierarchy:

```md
# Document Title

Brief description of the document purpose.

## Primary Section

Text or list content.

### Subsection

Detailed information.

## Next Section

Text content.
```

Recommended layout template:

```md
# Title

Brief overview: what this document covers and why it exists.

## Purpose

Scope and objectives of the document.

## Prerequisites

Required background knowledge, tools, or configurations.

## Core Content

Detailed specifications and technical guidance.

## Examples

Practical usage scenarios.

## Limitations

Known edge cases, trade-offs, or constraints.

## Related Documents

Cross-references and relative links to complementary documents.
```

Omit unnecessary sections when they do not apply to the specific topic.

---

## 3. Headings

Use a single top-level `#` heading and maintain sequential levels:

```md
# Level 1

## Level 2

### Level 3

#### Level 4
```

Never skip hierarchy levels:

```md
# Title

### Section
```

Skipping `##` makes document navigation and automatic outline generation disjointed.

Do not use headings merely to adjust text font sizes.

Incorrect:

```md
# Installation

### Dependency Setup

##### npm
```

Correct:

```md
# Installation

## Dependency Setup

### npm
```

---

## 4. Paragraphs

Structure paragraphs around a single coherent concept.

Incorrect:

```md
To run the project install Node.js after that install dependencies
and run npm install command then you can start the project.
```

Correct:

````md
The project requires Node.js.

Install required dependencies:

```bash
npm install
```

Start the application:

```bash
npm run dev
```
````

---

## 5. Lists

Use `-` for unordered itemization:

```md
- Node.js
- npm
- Docker
- PostgreSQL
```

Use numbered lists for chronological step-by-step procedures:

```md
1. Install dependencies.
2. Create `.env` configuration.
3. Apply database migrations.
4. Launch the application.
```

Do not mix marker styles within the same document:

```md
- Item
* Item
+ Item
```

Maintain consistent `-` dashes across the entire repository:

```md
- Item
- Item
- Item
```

---

## 6. Code Blocks

Use fenced code blocks with explicit language identifiers:

````md
```bash
npm install
npm run build
```
````

For JavaScript:

````md
```javascript
const result = await getData();
```
````

For TypeScript:

````md
```typescript
const result: User = await getUser();
```
````

For configuration:

````md
```yaml
server:
  port: 3000
```
````

For generic raw text output:

````md
```text
example output
```
````

Do not use inline backticks for multi-line snippets. Inline code is reserved for concise identifiers:

```md
Execute `npm install`.
Configuration parameters reside in `.env`.
```

---

## 7. Commands

Commands should be directly copy-pasteable:

````md
```bash
npm install
npm run test
npm run build
```
````

If execution depends on a specific directory or condition, document it immediately prior:

````md
Navigate to the project root:

```bash
cd project
```

Install dependencies:

```bash
npm install
```
````

Do not bury critical execution flags or arguments in prose paragraphs.

---

## 8. Tables

Use Markdown tables for structured data comparisons:

```md
| Parameter | Value | Description |
|---|---|---|
| `PORT` | `3000` | Server listen port |
| `HOST` | `localhost` | Server bind interface |
| `NODE_ENV` | `development` | Target runtime environment |
```

Do not force long text blocks or complex paragraphs into table cells. Use standard lists when reading ease outweighs tabular alignment.

---

## 9. Links

Use relative file links for internal repository references:

```md
See the [deployment guide](./deployment.md).
```

For anchoring to specific subsections:

```md
See [database configuration](./setup.md#database).
```

Do not insert bare URLs in body text when descriptive markdown anchor text is possible:

Incorrect:

```md
Documentation: https://example.com/docs
```

Correct:

```md
See the [official documentation](https://example.com/docs).
```

---

## 10. Files and Directories

Format file names, directory paths, environment variables, and command names with inline code:

```md
Configuration file: `.env`.

Core source code resides under `src/`.

Environment variable: `DATABASE_URL`.
```

---

## 11. Environment Variables

Document environment variables in a dedicated table:

```md
| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | Target database connection URI |
| `PORT` | No | HTTP listening port (default: 3000) |
| `LOG_LEVEL` | No | Logging verbosity (`info`, `debug`, `error`) |
```

Never commit real credentials, tokens, or passwords:

```md
DATABASE_PASSWORD=actual-secret-password
```

Use sanitized placeholders:

```md
DATABASE_PASSWORD=<password>
```

---

## 12. Warnings and Notes

Emphasize critical operational constraints using standard GitHub alert syntax:

```md
> [!NOTE]
> Local development requires a running Docker daemon.

> [!WARNING]
> This command truncates all local database tables.

> [!IMPORTANT]
> Pending schema migrations must be applied prior to deployment.
```

Do not abuse alerts for ordinary informative paragraphs.

---

## 13. Examples

Provide realistic, minimal, and reproducible examples.

Incorrect:

```md
Here is some example code that demonstrates many
different things that are not actually needed.
```

Correct:

````md
```typescript
const user = await getUser(userId);
```
````

If a snippet is abbreviated for clarity, indicate this explicitly:

```md
The snippet above demonstrates only the pertinent configuration subset.
```

---

## 14. README Structure

A `README.md` must immediately resolve the following questions:

1. What is this project?
2. Why does it exist?
3. How do you install it?
4. How do you run it?
5. How do you execute the test suite?
6. Where is the additional documentation located?

Recommended layout:

```md
# Project Name

Brief project synopsis.

## Requirements

External tools and runtime prerequisites.

## Installation

Step-by-step installation instructions.

## Configuration

Environment variables and configuration files.

## Usage

Practical command-line or API usage examples.

## Development

Local build, watch, and contribution instructions.

## Testing

Test suite execution procedures.

## Deployment

Production compilation, packaging, and release procedures.

## Documentation

Index of links to extended technical manuals.

## License

Repository licensing information.
```

---

## 15. Architecture Decision Records (ADRs)

Maintain ADRs as individual files per architectural decision:

```text
docs/
└── adr/
    ├── 001-use-postgresql.md
    ├── 002-use-redis.md
    └── 003-api-versioning.md
```

Structure:

```md
# ADR-001: PostgreSQL Database Engine

## Status

Accepted

## Context

Technical challenges, requirements, and constraints motivating the decision.

## Decision

The architectural choice and technical justification.

## Alternatives

Considered alternatives and reasons for rejection.

## Consequences

Positive outcomes, trade-offs, and downstream operational implications.
```

---

## 16. Phrasing and Tone

Use concrete, unambiguous, and direct statements.

Incorrect:

```md
You should somehow configure the database here.
```

Correct:

```md
Provision a PostgreSQL database and assign its connection URI to `DATABASE_URL`.
```

Avoid ambiguous hedging words:

- `maybe`
- `somehow`
- `approximately`
- `usually`
- `probably`
- `etc.`

When exceptions or non-deterministic behaviors exist, state their boundaries explicitly.

---

## 17. Information Flow

Structure documentation along a logical progression:

```text
Context → Requirements → Steps → Examples → Troubleshooting
```

First explain **what and why**, followed by **prerequisites**, then **concrete steps**, followed by **verifiable examples**, and concluding with **troubleshooting**.

---

## 18. Troubleshooting

Format diagnostic and failure resolutions consistently:

````md
## Troubleshooting

### Error: `ECONNREFUSED`

**Cause**

The PostgreSQL daemon is not running or listening on the target port.

**Resolution**

Check the container state:

```bash
docker compose ps
```

If stopped, restart the service:

```bash
docker compose up -d postgres
```
````

---

## 19. Consistent Terminology

Use uniform technical terms across the repository.

For example, do not alternate arbitrarily between:

```text
deployment
deploy
deployment process
release
publishing
```

when referring to the identical lifecycle stage.

Standardize casing for common tooling and platforms:

```md
PostgreSQL
Docker
Node.js
TypeScript
GitHub
```

---

## 20. Prohibited Elements

Do not use excessive punctuation or emojis:

```md
# !!!!! IMPORTANT !!!!!

## !!! WARNING !!!

### READ THIS!!!

:)

:D

🚀
🔥
💡
```

Avoid redundant decorative dividers:

```md
-------------------
*******************
===================
```

Use semantic Markdown headings to establish structural boundaries.

Do not number sections sequentially without descriptive titles:

```md
# Setup

Some text...

## Setup 2

Some more text...

## Setup 3
```

Section titles must summarize their contents.

---

## Minimum Repository Standard

```text
1. One topic per document.
2. Exactly one top-level `#` title per file.
3. Strictly sequential heading depth: # → ## → ###.
4. Single logical thought per paragraph.
5. Standard dash lists (-) for itemization.
6. Numbered lists for sequential procedural steps.
7. Terminal commands formatted in fenced code blocks with bash/shell syntax.
8. File names, directories, variables, and commands formatted via inline code.
9. Internal documents linked via relative repository paths.
10. Tables reserved exclusively for structured tabular data.
11. No credentials or secrets committed in documentation.
12. Zero emojis and zero decorative symbols.
13. No duplication of content across documents.
14. Direct, concise prose without conversational filler.
15. Commands and examples must be complete and copy-pasteable.
16. Verify Markdown prior to merging for broken relative links, heading violations, and lint issues.
```
