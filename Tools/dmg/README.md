# DMG packaging

`Tools/make-dmg.sh <app> <output.dmg> [volume-name]` generates the artwork and
packages the application using dmgbuild. It writes Finder metadata directly and
requires no Finder or AppleScript session. The release workflow installs the
pinned Python dependency before signing credentials are imported.

For local archives, install the tools once:

```sh
python3 -m venv .venv-dmg
.venv-dmg/bin/pip install -r Tools/dmg/requirements.txt
export PATH="$PWD/.venv-dmg/bin:$PATH"
make archive
```

`render-background.swift` draws the website-inspired artwork as a 640 × 520 point
TIFF with 1× and 2× representations. It uses AppKit's system font and contains
the eyebrow, heading, icon outlines, arrow, label backplates, instructions, and
footer. Finder supplies the actual app icon, Applications link, and filenames.
Keep the icon centers and window dimensions in `settings.py` aligned with the
artwork when adjusting the layout.

The resulting DMG is unsigned locally. The release workflow signs, notarizes,
and staples it after packaging, then generates the Sparkle appcast as before.
