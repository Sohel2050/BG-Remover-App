import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

/// Combines multiple processed images (e.g. from Batch Process or Collage)
/// into a single PDF file, one image per page — free, fully on-device,
/// no server or API involved.
class PdfExportService {
  static Future<File> createPdf(List<File> images) async {
    if (images.isEmpty) {
      throw Exception('No images to export');
    }

    final doc = pw.Document();

    for (final imageFile in images) {
      final bytes = await imageFile.readAsBytes();
      final image = pw.MemoryImage(bytes);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final outFile = File(
      '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }
}
