import 'dart:typed_data';

import 'csv_exporter_stub.dart' if (dart.library.io) 'csv_exporter_io.dart';

abstract class CsvExporter {
  static Future<String> saveCsv(
    Uint8List bytes, {
    required String fileName,
  }) async {
    return CsvExporterImpl.saveCsv(bytes, fileName: fileName);
  }
}
