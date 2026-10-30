# Terminal2 development

- Speak Japanese to the user. Write code comments in English.
- Native macOS app, minimum macOS 26. Use AppKit / SwiftUI and real Unix PTYs; do not replace it with a WebView or simulated terminal.
- The feature reference is fuba/terminal at the commit documented in docs/feature-parity.md.
- All project code is MIT licensed. Preserve SwiftTerm's license in the app bundle.
- Build with scripts/build.sh; test with scripts/test.sh. Both enforce reviewed dependencies older than 24 hours and the resolved lock file. Never silently update dependencies.
- Add meaningful regression tests before behavior changes. Use real PTYs and the temporary loopback OpenSSH integration test for transport changes.
- Keep AppKit and SwiftUI state on MainActor. ProcessBridge receives ordered main-queue callbacks; protect any cross-thread window-size reads.
- Keep app and terminal shortcuts in ShortcutAction / KeyChord. Update native menu equivalents and recorder UI from the same configuration; do not add hard-coded shortcuts. F11 is unassigned by default. Option arrows use xterm Alt-arrow sequences, not Emacs word-navigation bytes.
- Keep the connection panel outside the terminal window. Do not reintroduce fullSizeContentView or an in-window sidebar that mixes the terminal surface with titlebar content.
- Do not weaken SSH host-key checks, put passwords into configuration, enable clipboard reads from terminal programs, or permit remote graphics to read arbitrary local files.
- Runtime configuration and logs are private user data. Never commit them or screenshots of the user's SSH aliases / Tailscale network.
- Record material changes and validation in docs/. Review correctness and security directly. CI must remain manual / opt-in.
