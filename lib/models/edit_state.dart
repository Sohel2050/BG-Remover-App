import 'dart:io';
import 'package:flutter/foundation.dart';

/// Holds the current image editing state.
/// Undo/redo stacks and brush data will be added in Part 4/5.
class EditState extends ChangeNotifier {
  File? originalImage;
  File? processedImage; // result after background removal

  bool isProcessing = false;

  void setOriginalImage(File file) {
    originalImage = file;
    processedImage = null;
    notifyListeners();
  }

  void setProcessedImage(File file) {
    processedImage = file;
    notifyListeners();
  }

  void setProcessing(bool value) {
    isProcessing = value;
    notifyListeners();
  }

  void reset() {
    originalImage = null;
    processedImage = null;
    isProcessing = false;
    notifyListeners();
  }
}
