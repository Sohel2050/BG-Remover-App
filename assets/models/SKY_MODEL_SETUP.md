# Getting a sky-segmentation model (sky_seg.onnx)

Like `u2net.onnx`, this is a binary model file too large to write out
directly — you need to obtain and place it yourself.

## Where to get one
- Search for an ONNX export of a sky-segmentation model — e.g. models
  from the "SkyAR" project (Zhengxia Zou et al.) or any U-Net-style model
  trained on a sky-segmentation dataset (ADE20K's "sky" class works too).
  Many are published as PyTorch/TF checkpoints and need conversion to
  ONNX (`torch.onnx.export` / `tf2onnx`) if not already available in
  ONNX form.
- Look for something with input size 256x256 or 320x320 RGB and a single-
  channel (or 2-class) output mask — that matches what
  `sky_segmentation_service.dart` expects. If your model uses a different
  input size, update `_inputSize` in that file. If it outputs 2 channels
  (sky/not-sky logits instead of one sky-probability channel), you'll
  need to adjust `_maskToImage`/`_flattenToFloat32` to take a softmax/
  argmax over the channel dimension instead of using the raw values
  directly.

## Where to place it
```
assets/models/sky_seg.onnx
```

`pubspec.yaml` already declares `assets/models/` as an asset folder, so
no changes needed there — just add the file and run `flutter pub get`
again.

## Until you add the model
`SkySegmentationService.loadModel()` / `.replaceSky()` will throw a clear
error (asset not found) rather than silently doing nothing — the "Replace
Sky" button surfaces that error in a SnackBar so it's obvious the model
is missing rather than looking like a bug in the app.
