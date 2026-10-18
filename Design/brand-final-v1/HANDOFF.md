# Approved ribbon N logo

The user approved the blue / teal / orange rounded ribbon N on a white background. These assets were generated with the built-in image_gen tool using the approved image as an edit reference. The application code, existing application resources, build scripts, and product name have not been changed.

## Deliverables

- `logo-white-master.png`: original generated square PNG, 1254 × 1254 pixels, white background. This is a raster master, not a vector source.
- `logo-white-1024.png`, `logo-white-512.png`, `logo-white-256.png`, `logo-white-128.png`, `logo-white-64.png`, `logo-white-32.png`: resized PNG exports.
- `AppIcon.icns`: macOS icon with standard representations from 16 through 1024 pixels.
- `AppIcon.iconset/`: individual icon representations.
- `generation-prompt.txt`: exact prompt used for the master image.

## Visual direction

Preserve the rounded N silhouette, blue left upright, teal descending diagonal, orange right upright, and balanced white margins. Intended palette: blue `#4285F4`, teal `#34B6A0`, warm orange `#F6A548`, white background. These are the generation target colors; the generated raster may contain small color variations.

## Integration handoff

Product naming is still pending the user's choice. Integrate the selected asset only when requested by the user. The current package deliberately contains no wordmark or baked-in product name. Keep the white-background version as the primary logo. Do not substitute one of the earlier book or bridge concepts.

The ICNS was packaged from the PNG master with macOS sips and iconutil. No transparent version or editable vector source is included in this release.
