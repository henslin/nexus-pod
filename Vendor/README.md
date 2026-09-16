# Vendor

Third-party Swift packages the Lab wraps as experiments, vendored so every
clone (GitHub, the NAS, the phone build) has them without a submodule.

- **BorderBeamKit** and **ThinkingOrbsKit** — the SwiftUI ports from
  [Libraries.dev](https://github.com/Jakubantalik/Libraries.dev) by Jakub
  Antalik, MIT (see `LICENSE-Libraries.dev`). Copied from
  `packages/<lib>/ports/ios/<Kit>` at upstream commit `422180d` on 2026-09-15.
  To update: re-clone upstream into `Vendor/Libraries.dev` (ignored) and
  copy the two kit folders over these.

Gooey, Metal and Image have no SwiftUI ports upstream yet; the Lab builds
those natively with the same control structure.
