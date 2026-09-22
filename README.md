# Codex Notch Companion

macOS notch companion for Codex usage windows, reset credits, and optional local usage feeds.

## Prototype

Static HTML prototype in the repo root:

```bash
python3 -m http.server 4173
open http://127.0.0.1:4173
```

Fixtures live under `fixtures/` and mirror local aiusage / local-daily field shapes only. The prototype does not read credentials, write config, or trigger uploads.

## Native app

The SwiftUI + AppKit app lives in `macos/`. It shows a non-activating top panel aligned to the notch, expands for details, and can:

- fetch Codex quota / reset credits (via local ChatGPT auth)
- optionally fall back to a local aiusage HTTP endpoint
- optionally read a local daily CSV and local usage HTTP feed configured in Settings

No hardcoded third-party product paths are shipped. Configure local data sources in the in-app Settings window.
