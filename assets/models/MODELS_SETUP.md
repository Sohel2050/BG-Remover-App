# Models for the AI Tools screen (Object Removal, Upscale, Select Subjects)

**Auto-download:** `isnet-general-use.onnx` / `u2net.onnx` (background
removal), `lama_fp32.onnx`, `esrgan_x4.onnx` and `yolov8m-seg.onnx` are
downloaded automatically the first time they are used. Bundling a file in
`assets/models/` skips its download.

Same story as u2net.onnx and sky_seg.onnx: these are binary files, too
large to write out directly. Download each, drop it in `assets/models/`
with the exact filename below, then `flutter pub get` again.

## 1. Object Removal → `lama_fp32.onnx`
```
https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx
```
~196MB. Fixed 512×512 input (handled internally — the service crops a
region around your paintbrush strokes, so the rest of the photo stays
full quality). Apache-2.0 license.

## 2. Upscale 4× → `esrgan_x4.onnx`
Any of these work (same `SRVGGNetCompact`/RRDBNet Real-ESRGAN I/O
contract: input `[1,3,h,w]` float32 RGB [0,1], output `[1,3,4h,4w]`):
```
https://huggingface.co/SceneWorks/real-esrgan-onnx/resolve/main/real_esrgan_x4.onnx
```
or the general-purpose (denoising) variant:
```
https://huggingface.co/Saimon8420/realesr-general-x4v3-web/resolve/main/realesr-general-x4v3.onnx
```
BSD-3-Clause license (Real-ESRGAN, Xintao Wang et al.). Rename whichever
you pick to `esrgan_x4.onnx`.

## 3. Select Subjects → `yolov8m-seg.onnx`
Downloaded automatically on first use (~105MB). To bundle it instead,
download one of these and put it in `assets/models/`:
```
https://huggingface.co/unileon-robotics/YOLO8-ONNX/resolve/main/yolov8m-seg.onnx
```
Smaller option (~14MB, rougher masks): `yolov8n-seg.onnx` from the same
repo. If you use it, change the `yolo` entry in
`lib/services/model_store.dart` to that file name.

Both are Ultralytics YOLOv8 exports at 640x640 (output `1x116x8400` and
`1x32x160x160`), which is what `subject_detection_service.dart` expects.
AGPL-3.0 license (Ultralytics) — fine for personal/free use; check the
license terms if you plan to distribute the app commercially.

## What needs no model file
**Skin Smoothing** works immediately — it's a pure color/blur algorithm
(no AI), see `lib/services/face_retouch_service.dart`.

## If a model is missing
Each tool checks the asset exists before trying to load it, and shows a
clear "Model file missing" dialog with the exact filename — it won't
crash or silently do nothing.
