# Installing Variabe Search (guide for AI agents)

You are an AI coding agent (Claude, Cursor, Codex or similar) helping someone install Variabe Search, a macOS app that
searches their files by what's in them. Follow these steps in their terminal, explain each one in a sentence before
you run it, and stop to ask when something doesn't match. Everything here is for the person's own Mac.

## 1. Check the Mac

```sh
uname -m          # must print arm64 (Apple Silicon). x86_64 (Intel) isn't supported: stop and say so.
sw_vers -productVersion   # must be 14 or later
```

If either check fails, tell the person the app won't run on this Mac and stop. They could build from source instead
(see README.md), but Intel Macs aren't supported at all.

## 2. Download the latest release

```sh
DMG_URL=$(curl -fsSL https://api.github.com/repos/BarakaSoka/variabe-search/releases/latest \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' | cut -d'"' -f4)
echo "$DMG_URL"
mkdir -p ~/Downloads/variabe-install
curl -fL "$DMG_URL" -o ~/Downloads/variabe-install/VariabeSearch.dmg
```

If `DMG_URL` is empty, the GitHub API may be rate limited: send the person to
https://github.com/BarakaSoka/variabe-search/releases/latest to download the DMG by hand, then continue from step 3
with that file.

## 3. Install into Applications

If Variabe Search is already running (an update), quit it first: `osascript -e 'quit app "Variabe Search"'`.

```sh
MNT=$(mktemp -d)
hdiutil attach -nobrowse -quiet -mountpoint "$MNT" ~/Downloads/variabe-install/VariabeSearch.dmg
rm -rf "/Applications/Variabe Search.app"
ditto "$MNT/Variabe Search.app" "/Applications/Variabe Search.app"
hdiutil detach -quiet "$MNT"
rm -rf ~/Downloads/variabe-install
```

Replacing the app keeps the person's index, settings and downloaded model: those live in
`~/Library/Application Support/Variabe Search`, which you should never delete.

## 4. Allow it to open

The app isn't notarized by Apple yet, so macOS blocks the first launch. There are two ways through; ask the person
which they prefer.

- **In System Settings (no terminal):** run `open "/Applications/Variabe Search.app"`. When macOS says it can't verify
  the developer, click Done, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**,
  then confirm. This is needed only once per version.
- **In the terminal:** remove the download-quarantine flag from this one app, then open it:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/Variabe Search.app"
  open "/Applications/Variabe Search.app"
  ```

Never turn off Gatekeeper system-wide (`spctl --master-disable`) or change other security settings.

## 5. First launch: tell the person what to expect

- The app downloads its search model once (865 MB). It needs the internet for this, and never again after.
- It asks which folders to search. They can pick whole folders or only some subfolders, and it shows an estimate of
  how long the first pass takes. macOS may ask for permission to read folders like Documents or Desktop: they should
  click Allow.
- Indexing runs in the background. Nothing they index leaves the Mac.
- To search, they open Variabe Search (from Applications or with Spotlight) and type what the file is about, not its
  name. README.md lists the keyboard shortcuts.

## Updating later

There are no automatic updates yet. To update, run steps 2 and 3 again, then step 4. Check the installed version with:

```sh
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "/Applications/Variabe Search.app/Contents/Info.plist"
```

## Uninstalling

Quit the app, then delete `/Applications/Variabe Search.app`. To also remove the index, settings and model (several
GB at most), ask the person first, then delete `~/Library/Application Support/Variabe Search`.

## If something goes wrong

- **"damaged and can't be opened":** the quarantine flag is still set. Use either option in step 4.
- **The app opens but nothing shows:** it lives in the menu bar; look for its icon there.
- Anything else: send the person to https://github.com/BarakaSoka/variabe-search/issues with what they saw.
