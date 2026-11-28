<div align="center">

# [Typeflux Classic](https://typeflux.app) - Talk. We'll Type.

Hold `Fn` to dictate, or double-press `Fn` to ask anything. Typeflux delivers lightning-fast, accurate voice-to-text directly into any macOS application. Free, open-source, and supports local models — your voice never has to leave your Mac.

[![Tests](https://github.com/mylxsw/typeflux-classic/actions/workflows/test.yml/badge.svg)](https://github.com/mylxsw/typeflux-classic/actions/workflows/test.yml)

English | [简体中文](./README.zh-CN.md)

[![观看视频](https://img.youtube.com/vi/ZxWWUOEgaJ4/maxresdefault.jpg)](https://youtu.be/ZxWWUOEgaJ4)

![product-image](./assets/product-image.png)

[View more screenshots](./docs/SCREENSHOTS.md)

</div>


> [!NOTE]
> **Typeflux is now a full productivity app for Mac.** Beyond voice input, [Typeflux](https://github.com/mylxsw/typeflux) adds a launcher, Chat, an action Ring, clipboard history, screenshots, screen recording, and translation. Typeflux Classic stays focused on voice input and receives bug fixes and account updates; new features go to Typeflux.
>
> Both apps use the same account, subscription, and local data. Each installs as `Typeflux.app`, so installing [Typeflux](https://github.com/mylxsw/typeflux/releases/latest) replaces Classic and keeps your history and settings.

## Download

**[⬇ Download latest release (.dmg)](https://github.com/mylxsw/typeflux-classic/releases/latest)**

1. Download the Classic DMG for your Mac from the latest release
2. Open the DMG and drag `Typeflux.app` to **Applications**
3. Launch and grant Microphone + Accessibility permissions

> **macOS 13+** · Free · No subscription · Fully local inference supported

## Why Typeflux

Most voice input tools force you to switch apps — dictating in one place, then copying and pasting into another. That context switch breaks flow.

Typeflux injects text directly into whichever app you're already using, at the cursor position, the moment you release the hotkey. It feels like typing, just **4× faster** (~200 WPM vs. ~50 WPM).

And when you need more than dictation, **Ask Anything** turns your voice into an AI assistant for Q&A, rewriting, translation, and complex workflows.

## How It Works

```
Hold Fn → Speak → Release → Text appears instantly
Fn ×2 → Ask → Release → Answer, edit, or action
```

1. **Press and hold** `Fn` (default hotkey)
2. **Speak naturally**
3. **Release** — Typeflux transcribes and injects the text at your cursor
4. **Double-press** `Fn` to use Ask Anything for Q&A, selected-text edits, and agent workflows
5. The result is also copied to clipboard as a fallback

## Features

### One-Click Voice Input
Hold `Fn` to start, release to stop. No switching input methods, no clicking buttons — works in any text field across browsers, code editors, terminals, and native apps.

### Ask Anything (`Fn` ×2)
More than just dictation. Double-press `Fn`, speak on the second press, then release to chat with an AI agent using your voice:

- **Voice Q&A** — Ask questions and get instant answers
- **Content Rewrite** — Select text, then speak an instruction like "make this shorter" or "translate to English"
- **Complex Workflows** — Handle multi-step tasks through natural conversation

### Local-First, Privacy-First
Run entirely on your Mac with on-device models. No API keys needed, no data leaves your machine. We don't collect, store, or analyze any of your voice or text data.

### Custom Personas
Create named instruction sets for different scenarios — work emails, study notes, casual chat, code comments — and switch between them from the menu bar.

### Multiple Speech Backends
| Provider | Type | Best For |
|----------|------|----------|
| Typeflux Cloud | Cloud | Zero-config, balanced accuracy |
| Local Model | Local | Privacy, offline use |
| Alibaba Cloud ASR | Cloud streaming | Low latency, Chinese |
| Doubao Realtime ASR | Cloud streaming | Chinese optimization |
| Google Speech-to-Text | Cloud | Multi-language, enterprise |
| OpenAI (Whisper API) | Cloud | High accuracy |
| Multimodal LLM | Cloud | Vision + audio tasks |
| Groq | Cloud | Fast inference, low cost |
| Free Models | Cloud | No API key, open-source endpoints |

### Local Models
When you choose **Local Model**, Typeflux downloads and runs the model entirely on your Mac:

| Model | Size | Params | Best For |
|-------|------|--------|----------|
| SenseVoice | ~350 MB | 234M | Fast multilingual, strong Mandarin/Cantonese/English/Japanese/Korean |
| FunASR (Paraformer) | ~180 MB | 220M | Fast, accurate Chinese-focused offline ASR |
| WhisperKit Medium | ~1.5 GB | 769M | Balanced English and multilingual dictation |
| WhisperKit Large | ~3 GB | 1.55B | Highest accuracy offline transcription |
| Qwen3-ASR | ~1.3 GB | 0.6B | Strong context understanding, long-form recognition |

### Streaming Preview
See partial transcription results while still speaking, so you get immediate feedback before you release.

### History & Replay
Every session is saved locally. Review past sessions, replay audio, retry transcription with different settings, or export records to Markdown.

## Requirements

- macOS 13 or later
- Microphone permission
- Accessibility permission (for text injection)

For cloud providers: API keys and endpoint URLs.  
For local inference: model files are downloaded automatically on first use.

## Build from Source

```bash
git clone https://github.com/mylxsw/typeflux-classic
cd typeflux-classic

# One-time setup: create a local code-signing identity so macOS
# permissions (microphone, accessibility) persist across rebuilds.
scripts/setup_dev_cert.sh

make run          # build + launch as .app bundle
make dev          # launch with terminal logs attached
make full-dev     # launch dev app with bundled SenseVoice resources
make full-release # build the full notarized production installer locally
make release-continue # resume an interrupted local release
make test SUITE=TypefluxCloudRequestHeadersTests
```

CI builds the app and runs affected suites on pull requests to `main`.
Repository owners, members, and collaborators can rerun CI with `@autotest`.

The development bundle is installed at `~/Applications/Typeflux Classic Dev.app`.

See [CLAUDE.md](./CLAUDE.md) for the full development guide.

## Maintaining Classic

Typeflux Classic is the standalone macOS voice input edition derived from Typeflux 0.4.0.
It shares the local data, account, and subscription with Typeflux.

Backport an upstream fix from a branch based on Classic's `main`:

```bash
git remote add upstream https://github.com/mylxsw/typeflux.git # once per clone
git fetch upstream main
git cherry-pick -x <upstream-fix-sha>
```

Run the affected tests and open a pull request against Classic's `main`.

## Release setup

The release workflow produces `Typeflux-Classic-<version>-<arch>.{zip,dmg}`
for `apple-silicon` and `intel`. Both formats contain `Typeflux.app` and use
the minimal bundle with the local-model runtime. Use the Classic release page
as the server's `source_url`, for example
`https://github.com/mylxsw/typeflux-classic/releases/tag/v0.5.0`.

Configure these GitHub Actions secrets using the same names as in Typeflux:

- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `CODESIGN_IDENTITY`
- `APPLE_TEAM_ID`
- `NOTARYTOOL_APPLE_ID`
- `NOTARYTOOL_PASSWORD`

GitHub Actions provides `GITHUB_TOKEN` for release assets. The existing
`NOTIFICATION_REMOTE_URL` secret is optional.

## Documentation

- [Usage Guide](./docs/USAGE.md)
- [Make Commands](./docs/MAKE_COMMANDS.md)
- [Release Guide](./docs/RELEASE.md)
- [Changelog](./CHANGELOG.md)

## Community

Join the community to share feedback, ask questions, and follow development updates:

- [Join Discord](https://discord.com/invite/Vr5389YrN)
- [X](https://x.com/mylxsw)

## Contributing

Typeflux is a completely open-source project. We believe great tools should belong to everyone.

Contributions welcome — STT provider integrations, overlay UX, settings views, text injection edge cases, or history/export features are great starting points.

1. Read the module layout in [CLAUDE.md](./CLAUDE.md)
2. Run the app locally with `make dev`
3. Add or update tests for any logic changes
4. Open a PR with a description of user-visible impact

## License

AGPL-3.0. See [LICENSE](./LICENSE).
