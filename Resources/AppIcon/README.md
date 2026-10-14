# Variabe Search's icon: "Lens"

A magnifier with a rounded-square lens, in Liquid Glass and Spotlight's neutral grays: light gray in Light Mode, dark
gray in Dark Mode. No hues.

- `appicon.svg`: the app icon (1024 × 1024, macOS icon grid). `../AppIcon.icns` holds it at 64 px and up.
- `appicon-small.svg`: the same with heavier strokes, so it holds up at 16 and 32 px. `../AppIcon.icns` holds it
  at those sizes. (Older macOS shows the `.icns`; it's the light version, drawn with its own glassy highlights.)
- `AppIcon.icon`: the design as Liquid Glass layers for macOS 26 and later (an Icon Composer document): a gradient
  fill and one glass layer, the lens, with a light and a dark color (`fill-specializations`), so the
  icon follows the system appearance. `build.sh` compiles it into `Assets.car` with `actool`; `Info.plist`'s
  `CFBundleIconName` points at it. Draw these layers with fills only: actool fills stroked SVG paths, so a stroked
  ring comes out as a disc.
- `menubar.svg`: the menu bar mark in one color. The app draws it in code from the same geometry (`StatusIcon` in
  `Sources/VariabeApp/StatusMenu.swift`); while indexing, the lens fills up from the bottom as progress.

To rebuild `AppIcon.icns` after editing a source: render both SVGs at 1024 px (headless Chrome works:
`"Google Chrome" --headless=new --default-background-color=00000000 --window-size=1024,1024 --screenshot=out.png
file://…/appicon.svg`), scale them into an iconset (`icon_16x16.png`, `icon_16x16@2x.png` and `icon_32x32.png` from
`appicon-small.svg`; the other seven sizes, 64 to 1024 px, from `appicon.svg`), then
`iconutil -c icns AppIcon.iconset -o ../AppIcon.icns`.

Colors, light / dark: body #FAFAFB → #D4D4DA / #46464A → #19191B; lens #FFFFFF / #C7C7CC.
The app's palette (`Brand` in `Sources/VariabeApp/Components.swift`) is the same grays, resolved per appearance.
