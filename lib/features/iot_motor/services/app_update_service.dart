import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Resultado da verificação de atualização do app.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.installedVersion,
    required this.installedBuild,
    required this.publishedVersion,
    required this.publishedBuild,
    required this.commit,
    required this.apkUrl,
    required this.updateAvailable,
  });

  final String installedVersion;

  /// Selo do build gravado pelo CI (vazio em APK compilado à mão).
  final String installedBuild;
  final String publishedVersion;
  final String publishedBuild;
  final String commit;
  final String apkUrl;
  final bool updateAvailable;
}

/// Consulta o APK publicado pelo CI e diz se há versão nova.
///
/// O CI (android-apk.yml) publica `IoTMotor.apk` e `app-latest.json` no release
/// `app-latest`. A instalação em si é feita pelo Android, a partir do download.
class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const String manifestUrl =
      'https://github.com/frahncky/IoTMotor/releases/download/app-latest/app-latest.json';

  /// Gravado pelo CI com --dart-define=IOTMOTOR_BUILD=<data e hora>.
  static const String installedBuild = String.fromEnvironment(
    'IOTMOTOR_BUILD',
    defaultValue: '',
  );

  final http.Client _client;

  Future<AppUpdateInfo> check() async {
    final PackageInfo pacote = await PackageInfo.fromPlatform();
    final String instalada = '${pacote.version}+${pacote.buildNumber}';

    final http.Response resposta = await _client
        .get(Uri.parse(manifestUrl))
        .timeout(const Duration(seconds: 15));
    if (resposta.statusCode != 200) {
      throw Exception('GitHub respondeu ${resposta.statusCode}');
    }

    final Map<String, dynamic> dados =
        jsonDecode(resposta.body) as Map<String, dynamic>;
    final String publicada = (dados['version'] ?? '').toString();
    final String build = (dados['build'] ?? '').toString();

    return AppUpdateInfo(
      installedVersion: instalada,
      installedBuild: installedBuild,
      publishedVersion: publicada,
      publishedBuild: build,
      commit: (dados['commit'] ?? '').toString(),
      apkUrl: (dados['apk'] ?? '').toString(),
      // A versão do pubspec não muda a cada commit, então o selo do build é
      // quem diz se o APK publicado é mais novo. Sem selo (APK compilado à
      // mão), oferecemos o download em vez de afirmar que está atualizado.
      updateAvailable:
          build.isNotEmpty && (installedBuild.isEmpty || build != installedBuild),
    );
  }

  void dispose() => _client.close();
}
