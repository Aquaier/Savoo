import 'dart:typed_data';

class CsvExporterImpl {
  static Future<String> saveCsv(
    Uint8List bytes, {
    required String fileName,
  }) async {
    throw UnsupportedError('CSV export nie jest dostępny na tej platformie.');
  }
}
