import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> writeHistoryCsv(String csv, String fileName) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  final File file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(csv, flush: true);
  return 'Exportado para ${file.path}';
}
