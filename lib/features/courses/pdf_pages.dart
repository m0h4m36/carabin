import 'package:pdfrx/pdfrx.dart';

/// Nombre de pages d'un PDF, ou null s'il n'a pas pu être lu.
Future<int?> countPdfPages(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    return doc.pages.length;
  } finally {
    doc.dispose();
  }
}
