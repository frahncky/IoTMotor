/// Nomes amigáveis das placas, os mesmos usados no painel web.
///
/// Os identificadores continuam valendo onde são necessários para configurar a
/// conexão; nas mensagens e nas listas, quem lê vê o nome da placa.
const Map<String, String> kNomesDasPlacas = <String, String>{
  'esp32-01': 'Quadro de comando',
  'esp32-02': 'Sensores do motor',
};

/// Nome da placa, ou o próprio identificador quando ele não é conhecido.
String nomeDaPlaca(String deviceId) {
  final String limpo = deviceId.trim();
  return kNomesDasPlacas[limpo] ?? limpo;
}

/// Nome com o identificador ao lado, para telas de configuração.
String nomeComId(String deviceId) {
  final String limpo = deviceId.trim();
  final String? nome = kNomesDasPlacas[limpo];
  return nome == null ? limpo : '$nome ($limpo)';
}
