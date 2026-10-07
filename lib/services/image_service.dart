import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles picking images from camera/gallery and basic permission checks.
/// AI inference lives in ai_service.dart (Part 2).
class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> requestGalleryPermission() async {
    // On Android 13+, photo access uses Permission.photos.
    final status = await Permission.photos.request();
    return status.isGranted || status.isLimited;
  }

  Future<File?> pickFromCamera() async {
    final granted = await requestCameraPermission();
    if (!granted) return null;

    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (shot == null) return null;
    return File(shot.path);
  }

  Future<File?> pickFromGallery() async {
    final granted = await requestGalleryPermission();
    if (!granted) return null;

    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return null;
    return File(picked.path);
  }
}
