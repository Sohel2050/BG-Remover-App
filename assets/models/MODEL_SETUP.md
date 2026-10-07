# Getting the u2net.onnx model (Part 2)

The model file itself (~176MB for full U2Net, ~4.7MB for the "lite"
version) is NOT included in the code — it's a binary asset too large to
write out here, and needs to be downloaded separately.

## Recommended: U2Net lite (small, mobile-friendly)

1. Download `u2netp.onnx` (the lite/portable version) from the official
   U2Net releases, or convert it yourself:
   - Original PyTorch weights: https://github.com/xuebinqin/U-2-Net
   - Pre-converted ONNX versions are also shared by the `rembg` project:
     https://github.com/danielgatis/rembg (uses `u2netp.onnx` /
     `u2net.onnx` internally, model URLs listed in their source)

2. Rename the downloaded file to exactly: `u2net.onnx`

3. Place it at:
   ```
   assets/models/u2net.onnx
   ```
   (replacing the `.gitkeep` placeholder in that folder)

4. Confirm `pubspec.yaml` already lists:
   ```yaml
   flutter:
     assets:
       - assets/models/
   ```
   (already added in Part 1)

5. Run `flutter pub get` again after adding the file so it gets bundled.

## Notes
- Input size expected by `ai_service.dart`: 320x320 RGB — matches
  standard U2Net export. If you use a differently-shaped model, update
  `_inputSize` in `lib/services/ai_service.dart`.
- The lite model (`u2netp.onnx`, ~4.7MB) is recommended for app size —
  full `u2net.onnx` (~176MB) gives slightly better edges but bloats the
  app significantly. You can swap models later without code changes as
  long as input/output shapes match.
- First run will be slower (model load into memory); subsequent
  `removeBackground()` calls on the same session are faster.
