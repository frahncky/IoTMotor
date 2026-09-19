import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Guarda os arquivos do app numa pasta temporária, como no celular.
class _PastaDeTeste extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _PastaDeTeste(this.pasta);
  final String pasta;

  @override
  Future<String?> getApplicationSupportPath() async => pasta;
  @override
  Future<String?> getApplicationDocumentsPath() async => pasta;
  @override
  Future<String?> getTemporaryPath() async => pasta;
}

void main() {
  late Directory pasta;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    pasta = await Directory.systemTemp.createTemp('iotmotor_settings');
    PathProviderPlatform.instance = _PastaDeTeste(pasta.path);
  });

  tearDown(() async {
    // No Windows o arquivo pode seguir aberto; limpeza é o melhor esforço.
    try {
      if (await pasta.exists()) await pasta.delete(recursive: true);
    } catch (_) {}
  });

  test('conexão MQTT digitada continua salva ao reabrir o app', () async {
    final MotorControlController primeiro = MotorControlController();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    primeiro.brokerController.text = 'test.mosquitto.org';
    primeiro.portController.text = '8883';
    primeiro.clientIdController.text = 'bancada_ifma';
    primeiro.topicPrefixController.text = 'iotmotor';
    primeiro.usernameController.text = 'francisco';
    // Digitar agenda a gravação; espera passar o atraso do debounce.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    primeiro.dispose();

    final File arquivo = File('${pasta.path}${Platform.pathSeparator}motor_settings_v1.json');
    expect(await arquivo.exists(), isTrue, reason: 'nada foi gravado no disco');
    expect(jsonDecode(await arquivo.readAsString())['settings']['broker'],
        'test.mosquitto.org');

    final MotorControlController segundo = MotorControlController();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(segundo.brokerController.text, 'test.mosquitto.org');
    expect(segundo.portController.text, '8883');
    expect(segundo.clientIdController.text, 'bancada_ifma');
    expect(segundo.usernameController.text, 'francisco');
    segundo.dispose();
  });

  test('broker digitado vence o perfil MQTT ao reabrir, e trocar de perfil manda', () async {
    const MqttConnectionConfig perfilA = MqttConnectionConfig(
      host: 'broker.hivemq.com',
      port: 1883,
      clientId: 'perfil_a',
      topicPrefix: 'iotmotor',
      deviceId: '',
      useTls: false,
    );
    const MqttConnectionConfig perfilB = MqttConnectionConfig(
      host: 'outro.broker.org',
      port: 1883,
      clientId: 'perfil_b',
      topicPrefix: 'iotmotor',
      deviceId: '',
      useTls: false,
    );

    // Abre no perfil A e digita outro broker.
    final MotorControlController primeiro =
        MotorControlController.withMqttConfig(perfilA, profileId: 'a');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    primeiro.brokerController.text = 'test.mosquitto.org';
    await Future<void>.delayed(const Duration(milliseconds: 800));
    primeiro.dispose();

    // Reabre no mesmo perfil: vale o que foi digitado.
    final MotorControlController segundo =
        MotorControlController.withMqttConfig(perfilA, profileId: 'a');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(segundo.brokerController.text, 'test.mosquitto.org');
    segundo.dispose();

    // Troca para o perfil B: quem manda é o perfil novo.
    final MotorControlController terceiro =
        MotorControlController.withMqttConfig(perfilB, profileId: 'b');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(terceiro.brokerController.text, 'outro.broker.org');
    terceiro.dispose();
  });

  test('abrir o app não apaga as configurações já salvas', () async {
    final File arquivo = File('${pasta.path}${Platform.pathSeparator}motor_settings_v1.json');
    await arquivo.writeAsString(jsonEncode(<String, dynamic>{
      'version': 1,
      'settings': <String, dynamic>{
        'broker': 'meu.broker.local',
        'port': '1883',
        'client_id': 'guardado',
        'topic_prefix': 'iotmotor',
        'username': '',
        'use_tls': false,
        'telemetry_alerts_enabled': true,
        'voltage_min': '190',
        'voltage_max': '240',
        'current_max': '10',
        'vibration_max': '1.5',
        'temperature_max': '70',
      },
    }));

    final MotorControlController controlador = MotorControlController();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(controlador.brokerController.text, 'meu.broker.local');
    expect(
      jsonDecode(await arquivo.readAsString())['settings']['broker'],
      'meu.broker.local',
      reason: 'a abertura do app sobrescreveu o arquivo com os padrões',
    );
    controlador.dispose();
  });
}
