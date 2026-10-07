# A note on Sky Replacement & Multiple Subject Detection

These two Part 10 items are **not implemented** in this codebase, and it's
worth being upfront about why, rather than faking something that doesn't
actually work well:

## Sky Replacement
This needs a *different* segmentation model trained specifically to find
sky regions (e.g. a sky-matting model). `u2net` (the model wired up in
Part 2) produces a single general "foreground vs background" saliency
mask — it has no concept of "sky" as a distinct category. Doing this
properly means bundling a second on-device model and a second inference
pipeline, similar in shape to `ai_service.dart` but with a sky-specific
network (e.g. `skyar` / `sky-seg` style ONNX models). It's a real,
free, on-device-feasible feature — just genuinely a separate model
integration, not something to bolt onto the existing pipeline.

## Multiple Subject Detection
`u2net`'s output is one combined saliency mask for "everything salient in
the frame" — it doesn't separate individual instances (person A vs
person B vs a dog). Real multi-instance selection needs an instance
segmentation model (e.g. a mobile-friendly Mask R-CNN / YOLACT variant)
that outputs a separate mask per detected object, plus UI for the user to
tap and pick which instance(s) to keep. This is a meaningfully bigger
undertaking than the brush-based single-mask editing already built in
Parts 4-6, and would be its own multi-part effort (model integration +
per-instance mask storage + tap-to-select UI + per-instance
erase/restore).

## If you want to pursue these later
Both are legitimate, fully-free, on-device-feasible features — they just
need their own model files and their own inference services (following
the same pattern as `AiService` in `lib/services/ai_service.dart`), not
an extension of the existing single-mask U2Net pipeline.
