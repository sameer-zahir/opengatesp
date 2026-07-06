# 13 — The in-app AI assistant (bring your own model)

The **Assistant** tab lets you drive OpenGateSP in plain English — *"show external sharing on
/sites/Marketing"*, *"which Microsoft 365 Groups have no owner?"* — using **your own AI model**.
Nothing is bundled and there is no subscription: paste a key you already have, or point it at a
model running on your own machine.

The assistant runs the same engine the GUI and the MCP server use. Every tool call shows the
**exact PowerShell it ran**, with a *Copy script* button, so you can always see and repeat what
happened.

## Pick a provider

| Provider | Key needed? | Where to get it |
|---|---|---|
| **Claude (Anthropic)** | Yes | [console.anthropic.com](https://console.anthropic.com/) → API keys. Default model: `claude-sonnet-5`. |
| **OpenAI** | Yes | [platform.openai.com](https://platform.openai.com/api-keys) → API keys. Default model: `gpt-5.5`. |
| **Ollama (local)** | **No** | Install [Ollama](https://ollama.com/), run `ollama pull llama3.1`, and just start it. Nothing leaves your machine. |
| **LM Studio (local)** | **No** | Install [LM Studio](https://lmstudio.io/), load a model, and start its local server. |

Setup is three fields on the AI page: pick the provider, keep or change the model, paste the key
(local providers skip the key). **Test** checks the connection; **Save** stores it.

## Where your key lives

- The key is encrypted with **Windows DPAPI** (your Windows account, this machine) and stored in
  `%APPDATA%\OpenGateSP\aiconfig.json`. It is **never written in plain text**, never leaves your
  machine, and no other Windows user can decrypt it.
- Your prompts — and the results of the reports the assistant runs — are sent to the provider you
  chose (Anthropic, OpenAI, or your own machine for Ollama / LM Studio). With a local model,
  nothing leaves your machine at all.

## What it can do

**Read-only reports (always available).** External sharing, permissions (report + matrix),
orphaned users, Everyone/EEEU oversharing, ownerless Microsoft 365 Groups, the consolidated
governance review, Explore source assessment, checked-out files, large files, and tenant
inventory — the same read-only surface as the [MCP server](../mcp-server/README.md).

**Write actions (off by default).** Turn on **"Allow write actions"** on the AI page to add:
migrate a folder into a library, create a site, bulk metadata from CSV, bulk check-in, trim
version history, restore permission inheritance, remove orphaned users, and lock/archive/unlock a
site.

Write actions follow a strict, code-enforced **preview-first contract** — the same rule as the
Copy wizard's *Run is locked until you Preview*:

1. Every write runs as a **preview** first. Nothing changes; you see exactly what *would* happen.
2. The assistant shows you the preview and asks you to confirm **in the chat**.
3. Only then does the same action run for real — and only if it matches the previewed one. If the
   assistant changes any detail (a different site, a different folder), it is forced back to a
   preview.

With the toggle **off**, the model never even sees the write tools — the assistant is strictly
read-only.

## Prefer your own AI app?

**Add to Claude Desktop** (on the AI page) registers OpenGateSP's [MCP server](../mcp-server/README.md)
in Claude Desktop, so you can drive the same tools from there — or from Codex, Cursor, or any MCP
client. The MCP server exposes the full tool surface, including the copy/migration tools.

## Troubleshooting

- **"Failed: …" on Test** — for cloud providers, re-check the key (paste it fresh; keys are long)
  and that your network allows `api.anthropic.com` / `api.openai.com`. For local providers, start
  Ollama (`ollama serve`) or LM Studio's server first, and check the endpoint field
  (`http://localhost:11434/v1` for Ollama, `http://localhost:1234/v1` for LM Studio).
- **"Connect your AI first"** — pick a provider and model, then **Save**.
- **The assistant says it can't change anything** — that's the read-only default. Enable
  **Allow write actions** on the AI page if you want it to fix what it finds.
- **A report needs a connection** — connect to your tenant first (the **Connect** view); the
  assistant uses the same connection as the rest of the app.
