# Nomi logo

The approved full green leaf has a rounded lower-left corner and a flat mint highlight. Body: `#20B68A`; highlight: `#8EDDBA`.

- `AppIcon.icns`: white-background macOS application icon, used by `scripts/build-app.sh`.
- `logo-white.svg` and `logo-white-4096.png`: white-background master artwork.
- `logo-transparent.svg` and `logo-transparent-4096.png`: transparent master artwork with the original presentation margins.
- `logo-in-app.svg`: transparent artwork with tighter framing for in-app use. It renders into `Sources/LectureNoteApp/Resources/AppLogo.png` at 1024 × 1024 pixels.

All interface logo placements use the shared `BrandLogo` component and the transparent resource. Do not add a tile background or clip it to a rounded square. The top-bar logo is 32 points and centered in the same 72-point column as the navigation rail.

The SVG files contain editable paths and uniform solid colors; they do not embed bitmaps, gradients, or textures.
