// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

Future<String> writeHistoryCsv(String csv, String fileName) async {
  final String uri =
      Uri.dataFromString(csv, mimeType: 'text/csv', encoding: utf8).toString();
  final html.AnchorElement anchor =
      html.AnchorElement(href: uri)
        ..download = fileName
        ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return 'Download iniciado: $fileName';
}
