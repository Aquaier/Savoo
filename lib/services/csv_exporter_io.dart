import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class CsvExporterImpl {
  static Future<String> saveCsv(
    Uint8List bytes, {
    required String fileName,
  }) async {
    Directory? targetDirectory;

    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        targetDirectory = downloadDir;
      } else {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          targetDirectory = Directory('${externalDir.path}/Download');
        }
      }
    } else {
      targetDirectory = await getDownloadsDirectory();
    }

    targetDirectory ??= await getApplicationDocumentsDirectory();
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }

    final file = File('${targetDirectory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
