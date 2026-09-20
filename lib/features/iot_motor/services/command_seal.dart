import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Sela os comandos com a senha combinada com as placas (AES-256-GCM).
///
/// Mesma conta do firmware (`comando_seguro.h`) e do painel
/// (`command-seal.js`): a chave de cada placa é
/// `SHA-256("iotmotor-cmd-v1" | senha | device_id)`. O identificador da placa
/// entra como dado autenticado, então um comando selado para o quadro de
/// comando não vale para os sensores.
///
/// Contra repetição, a placa publica um desafio em `<prefixo>/<placa>/auth` e
/// só aceita o comando que trouxer o desafio da vez.
class CommandSeal {
  static const String _rotulo = 'iotmotor-cmd-v1';

  final AesGcm _aes = AesGcm.with256bits();
  final Map<String, SecretKey> _chaves = <String, SecretKey>{};
  final Map<String, _EstadoDaPlaca> _placas = <String, _EstadoDaPlaca>{};
  String _senha = '';

  String get senha => _senha;
  bool get temSenha => _senha.isNotEmpty;

  set senha(String nova) {
    final String limpa = nova.trim();
    if (limpa == _senha) return;
    _senha = limpa;
    _chaves.clear();
  }

  /// Guarda o que a placa publicou em `auth`: se exige selo e o desafio atual.
  void registrarAuth(String placa, Map<String, dynamic> dados) {
    if (dados['device_id'] != placa) return;
    _placas[placa] = _EstadoDaPlaca(
      exigeSelo: dados['secure'] == true,
      desafio: dados['challenge'] is String ? dados['challenge'] as String : '',
    );
  }

  void esquecer([String? placa]) {
    if (placa == null) {
      _placas.clear();
    } else {
      _placas.remove(placa);
    }
  }

  bool exigeSelo(String placa) => _placas[placa]?.exigeSelo ?? false;

  /// Por padrão nenhuma placa exige senha: a tela só pergunta se alguma exigir.
  bool get algumaExigeSelo =>
      _placas.values.any((_EstadoDaPlaca placa) => placa.exigeSelo);

  /// Por que um comando não sairia agora — `null` quando está tudo pronto.
  String? impedimento(String placa) {
    if (!exigeSelo(placa)) return null;
    if (_senha.isEmpty) {
      return 'Informe a senha de comando nas configurações para comandar esta placa.';
    }
    if (_placas[placa]!.desafio.isEmpty) return 'Aguardando o desafio da placa.';
    return null;
  }

  /// Texto pronto para publicar quando a placa **não** exige selo.
  ///
  /// Devolve `null` quando o comando precisa ser cifrado, e aí quem chama usa
  /// [empacotar], que é assíncrono.
  String? empacotarAberto(String placa, Map<String, dynamic> comando) =>
      exigeSelo(placa) ? null : jsonEncode(comando);

  Future<SecretKey> _chaveDe(String placa) async {
    final SecretKey? guardada = _chaves[placa];
    if (guardada != null) return guardada;
    final Hash resumo = await Sha256().hash(
      utf8.encode('$_rotulo$_senha$placa'),
    );
    final SecretKey chave = SecretKey(resumo.bytes);
    _chaves[placa] = chave;
    return chave;
  }

  /// Cifra o comando para a placa, com o desafio da vez.
  Future<String> empacotar(String placa, Map<String, dynamic> comando) async {
    if (!exigeSelo(placa)) return jsonEncode(comando);
    final String? impede = impedimento(placa);
    if (impede != null) throw StateError(impede);

    final SecretBox caixa = await _aes.encrypt(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          ...comando,
          'ch': _placas[placa]!.desafio,
        }),
      ),
      secretKey: await _chaveDe(placa),
      aad: utf8.encode(placa),
    );
    final Uint8List junto = Uint8List.fromList(<int>[
      ...caixa.nonce,
      ...caixa.cipherText,
      ...caixa.mac.bytes,
    ]);
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'device_id': placa,
      'sealed': base64Encode(junto),
    });
  }
}

class _EstadoDaPlaca {
  const _EstadoDaPlaca({required this.exigeSelo, required this.desafio});

  final bool exigeSelo;
  final String desafio;
}
