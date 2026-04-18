# App Icon — Cinematic Liquid Glass

Target aesthetic: Apple's 2025 "Liquid Glass" icon language as seen in the SunExpress reference (photorealistic 747 cockpit, warm interior glow against a deep navy sky, sunset horizon in the lower-right, translucent glass sheen on the rounded-square frame).

## Required output

- **File:** `BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- **Size:** 1024 × 1024 px, exact
- **Format:** PNG, **no alpha channel**, sRGB color space
- **Corners:** leave the artwork as a full square — iOS applies the rounded-corner mask; do not pre-round
- **No text, no watermarks** — App Store rejects icons with text

Once you drop the file at that path, the next ship (`scripts/ship-to-testflight.sh` or the hourly cron) picks it up automatically. The `Contents.json` already references it.

## Concept options (pick one, or generate all three and choose)

### A. Bat meets ball (hero contact)
Close-up, cinematic shot of a wooden baseball bat at the exact moment of contact with the ball. Ball is just starting to deform against the wood grain. Subtle splinters and chalk dust in the air. Shallow depth of field.

### B. Stitches in flight
Macro of a single baseball suspended mid-flight, crystal-sharp red stitching catching warm rim light. Slight motion trail behind. Stadium bokeh blurred into the background.

### C. Silhouette swing at dusk
A batter silhouetted mid-swing against a deep-navy sky turning to warm orange at the horizon. Ball mid-frame, frozen. Stadium light towers flaring in bokeh. The figure is readable but nearly a silhouette — mood over detail.

## Prompts

### Midjourney v6 / v7

```
cinematic photorealistic iOS app icon, rounded square composition, close-up of a wooden baseball bat striking a baseball at the exact moment of contact, red stitching on the ball tack-sharp, subtle splinters and chalk dust catching warm rim light, deep navy sky fading to sunset orange on the lower right, stadium light flares in soft bokeh, translucent Liquid Glass highlights on the icon surface, volumetric lighting, shallow depth of field, premium Apple App Store icon aesthetic, centered composition, no text, no watermarks, 1:1, ultra detailed --ar 1:1 --style raw --v 6
```

For concept B, swap the subject line:
```
close-up macro of a single baseball suspended mid-flight, ultra-sharp red stitching catching warm rim light, faint motion trail dissolving behind the ball
```

For concept C:
```
silhouette of a baseball batter at the apex of a swing, bat fully extended, ball suspended inches from the bat, deep navy sky behind turning to warm sunset orange on the lower right, stadium light flares in heavy bokeh, the figure mostly silhouetted with a thin warm rim light
```

### DALL·E 3 (ChatGPT)

```
A photorealistic iOS app icon in the premium Apple "Liquid Glass" aesthetic. Square 1024×1024. Subject: a wooden baseball bat striking a baseball at the exact moment of contact, red stitching tack-sharp, subtle wood splinters and chalk dust in the air. Deep navy sky as background, with a warm sunset glow emerging from the lower-right corner. Stadium floodlight flares as soft bokeh. Translucent glassy highlights on the icon surface. Cinematic volumetric lighting, shallow depth of field. No text anywhere. No watermark. Square aspect ratio, centered composition.
```

### Adobe Firefly

Use the Firefly image generator with: content type = "Art", style = "Photo", with the same subject description. Set aspect ratio 1:1, resolution 2048 (downsize to 1024 after).

## After generation

1. Rename to `AppIcon.png`.
2. Strip alpha (Apple rejects icons with transparency):
   ```bash
   sips -s format png --deleteColorManagement --setProperty format png AppIcon.png
   # or, if you have ImageMagick:
   magick AppIcon.png -background black -alpha remove -alpha off AppIcon.png
   ```
3. Verify dimensions and alpha:
   ```bash
   sips -g pixelWidth -g pixelHeight -g hasAlpha AppIcon.png
   # expect: pixelWidth=1024, pixelHeight=1024, hasAlpha=no
   ```
4. Drop it at `BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (overwrites the placeholder).
5. `git add` + `git commit -m "Add cinematic app icon"` + `git push origin main`.
6. The hourly LaunchAgent will ship the new icon on its next tick (or run `scripts/ship-to-testflight.sh --auto-notes` to ship immediately).

## Why not let Claude generate this directly?

Claude Code does not have an image-generation tool in this harness — only image-*reading*. Photorealistic icon art is firmly a job for a dedicated image model. The current `AppIcon.png` in the repo is a vector silhouette placeholder I drew programmatically so the build would succeed; it is not intended to ship.
