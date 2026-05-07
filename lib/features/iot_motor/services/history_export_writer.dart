import 'history_export_writer_stub.dart'
    if (dart.library.io) 'history_export_writer_io.dart'
    if (dart.library.html) 'history_export_writer_web.dart'
    as impl;

Future<String> writeHistoryCsv(String csv, String fileName) {
  return impl.writeHistoryCsv(csv, fileName);
}
