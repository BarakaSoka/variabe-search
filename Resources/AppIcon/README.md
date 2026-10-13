# Variabe Search's icon: "Lens"

A magnifying lens with a V inside it — search, and Variabe — on a deep indigo body lit by a violet and a cyan glow.

- `appicon.svg`: the app icon (1024 × 1024, macOS icon grid). `../AppIcon.icns` holds it at 64 px and up.
- `appicon-small.svg`: the same with heavier strokes, so the V survives at 16 and 32 px. `../AppIcon.icns` holds it
  at those sizes.
- `AppIcon.icon`: the same design as layers for macOS 26 and later (an Icon Composer document: a #17133E fill, the
  aurora glow, the lens). `build.sh` compiles it into `Assets.car` with `actool`; `Info.plist`'s `CFBundleIconName`
  points at it. Older macOS uses the `.icns` (`CFBundleIconFile`).
- `menubar.svg`: the menu bar mark, the lens and V in one color. The app draws it in code from the same geometry
  (`StatusIcon` in `Sources/VariabeApp/StatusMenu.swift`); while indexing, the lens's ring fills up as progress.

To rebuild `AppIcon.icns` after editing a source: render both SVGs at 1024 px (headless Chrome works:
`"Google Chrome" --headless=new --default-background-color=00000000 --window-size=1024,1024 --screenshot=out.png
file://…/appicon.svg`), scale them into an iconset (`icon_16x16.png`, `icon_16x16@2x.png` and `icon_32x32.png` from
`appicon-small.svg`; the other seven sizes, 64 to 1024 px, from `appicon.svg`), then
`iconutil -c icns AppIcon.iconset -o ../AppIcon.icns`.

Colors: body #241C5C → #0B0C24; glow #7C5CFF and #22D3EE; lens #F5F3FF, handle #E9E5FF → #B9AEFF; the V
#5EEAD4 → #38BDF8 → #A78BFA. The app's palette (`Brand` in `Sources/VariabeApp/Components.swift`) comes from the same
colors.
