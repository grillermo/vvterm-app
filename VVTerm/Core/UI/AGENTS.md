# Shared UI Rules

These rules also apply to feature UI that uses shared presentation.

## Structure

- Prefer native Apple UI. Keep shared `Type.swift` focused on neutral contracts and state; put differing layout, lifecycle, modifiers, or adapters in a `Type+iOS.swift` companion.
- The app ships iOS only. Do not reintroduce `#if os(macOS)` gates, AppKit imports, or macOS companion files.
- Use neutral product UI type names. Platform prefixes are appropriate for true UIKit adapters and app-shell bridges.

## Presentation

- Never apply glass to terminal content. Use existing adaptive glass helpers for supported controls and preserve supported-OS fallbacks.
- Keep blocking states local to their screen.
- Use `Core/UI/Notices` for shared non-blocking presentation: one top banner for persistent or degraded state and ID-keyed bottom operations for user-initiated progress or failure.
- Scope notice hosts to the app or feature surface. Do not add a global toast bus or move feature policy into Core UI.
- Keep destructive decisions in native alerts and confirmation dialogs.
