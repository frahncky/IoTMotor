import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/services/command_seal.dart';

/// Vetor gerado fora do app, com a mesma conta do firmware e do painel:
/// chave = SHA-256("iotmotor-cmd-v1" | senha | device_id), AES-256-GCM,
/// dado autenticado = device_id, e o texto cifrado é iv || cifra || tag.
const String kSenha = 'senha-de-bancada';
const String kPlaca = 'esp32-01';
const String kSelado =
    'AAECAwQFBgcICQoLQEvZ40KMQt/6IvBMbFh3BlESiWt+qQFEyMr5+wr1GzgyIh2edSMMLF8o'
    'zvTIoqOmhyPA6mLFLJqMzgskikKc7mps9Uw/djwoVqGu0EmAUt4QavBTNt+2YDtsu0XnwlkG'
    'WezwMhCHjpjAbK3ytI30+dI=';
const String kTextoEsperado =
    '{"v":1,"device_id":"esp32-01","seq":"42","action":"stop",'
    '"ch":"ffffffffffffffffffffffffffffffff"}';

const String kDesafio = 'ffffffffffffffffffffffffffffffff';

Map<String, dynamic> _auth({bool secure = true, String desafio = kDesafio}) =>
    <String, dynamic>{
      'device_id': kPlaca,
      'secure': secure,
      'challenge': desafio,
    };

/// Abre um selo do mesmo jeito que a placa abre.
Future<String> abrirComoAPlaca(String selado, String senha, String placa) async {
  final Map<String, dynamic> pacote =
      jsonDecode(selado) as Map<String, dynamic>;
  final List<int> bruto = base64Decode(pacote['sealed'] as String);
  final Hash resumo = await Sha256().hash(
    utf8.encode('iotmotor-cmd-v1$senha$placa'),
  );
  final List<int> aberto = await AesGcm.with256bits().decrypt(
    SecretBox(
      bruto.sublist(12, bruto.length - 16),
      nonce: bruto.sublist(0, 12),
      mac: Mac(bruto.sublist(bruto.length - 16)),
    ),
    secretKey: SecretKey(resumo.bytes),
    aad: utf8.encode(placa),
  );
  return utf8.decode(aberto);
}

void main() {
  test('o app abre o selo produzido fora dele: mesma conta de chave', () async {
    final String aberto = await abrirComoAPlaca(
      jsonEncode(<String, dynamic>{
        'v': 1,
        'device_id': kPlaca,
        'sealed': kSelado,
      }),
      kSenha,
      kPlaca,
    );
    expect(aberto, kTextoEsperado);
  });

  test('placa sem senha continua recebendo comando aberto', () {
    final CommandSeal seal = CommandSeal()..senha = kSenha;
    seal.registrarAuth(kPlaca, _auth(secure: false));
    expect(seal.exigeSelo(kPlaca), isFalse);
    expect(seal.impedimento(kPlaca), isNull);
    expect(
      seal.empacotarAberto(kPlaca, <String, dynamic>{'action': 'stop'}),
      '{"action":"stop"}',
    );
  });

  test('com senha, o comando sai cifrado e com o desafio da vez', () async {
    final CommandSeal seal = CommandSeal()..senha = kSenha;
    seal.registrarAuth(kPlaca, _auth());
    expect(seal.empacotarAberto(kPlaca, <String, dynamic>{}), isNull);

    final String selado = await seal.empacotar(kPlaca, <String, dynamic>{
      'v': 1,
      'device_id': kPlaca,
      'seq': '42',
      'action': 'stop',
    });
    expect(selado.contains('stop'), isFalse, reason: 'não pode viajar legível');
    expect(await abrirComoAPlaca(selado, kSenha, kPlaca), kTextoEsperado);
  });

  test('senha errada ou outra placa não abrem o selo', () async {
    final CommandSeal seal = CommandSeal()..senha = kSenha;
    seal.registrarAuth(kPlaca, _auth());
    final String selado = await seal.empacotar(kPlaca, <String, dynamic>{
      'action': 'stop',
    });
    await expectLater(
      abrirComoAPlaca(selado, 'outra-senha', kPlaca),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      abrirComoAPlaca(selado, kSenha, 'esp32-02'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('sem senha ou sem desafio o app avisa em vez de publicar', () async {
    final CommandSeal seal = CommandSeal();
    seal.registrarAuth(kPlaca, _auth());
    expect(seal.impedimento(kPlaca), contains('senha de comando'));
    await expectLater(
      seal.empacotar(kPlaca, <String, dynamic>{}),
      throwsA(isA<StateError>()),
    );

    seal.senha = kSenha;
    seal.registrarAuth(kPlaca, _auth(desafio: ''));
    expect(seal.impedimento(kPlaca), contains('desafio'));
  });

  test('auth de outra placa é ignorado e esquecer derruba o desafio', () {
    final CommandSeal seal = CommandSeal()..senha = kSenha;
    seal.registrarAuth(kPlaca, <String, dynamic>{
      'device_id': 'esp32-02',
      'secure': true,
      'challenge': 'a' * 32,
    });
    expect(seal.exigeSelo(kPlaca), isFalse);
    seal.registrarAuth(kPlaca, _auth());
    expect(seal.exigeSelo(kPlaca), isTrue);
    seal.esquecer(kPlaca);
    expect(seal.exigeSelo(kPlaca), isFalse);
  });
}
