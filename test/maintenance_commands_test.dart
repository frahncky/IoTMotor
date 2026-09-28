import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/settings/device_maintenance_section.dart';

/// Registra os comandos de manutenção em vez de publicar no broker.
class _ServicoFalso extends MqttMotorService {
  final List<(String, String?)> enviados = <(String, String?)>[];
  final List<(String, String, Map<String, dynamic>)> comandos =
      <(String, String, Map<String, dynamic>)>[];

  @override
  MqttConnectionConfig? get activeConfig => const MqttConnectionConfig(
    host: 'localhost',
    port: 1883,
    clientId: 'teste',
    topicPrefix: 'iotmotor',
    deviceId: 'auto',
    useTls: false,
  );

  @override
  String? sendMaintenanceCommand(String action, {String? deviceId}) {
    enviados.add((action, deviceId));
    return enviados.length.toString();
  }

  @override
  String? sendRawCommand({
    required String deviceId,
    required String action,
    Map<String, dynamic> body = const <String, dynamic>{},
  }) {
    comandos.add((deviceId, action, Map<String, dynamic>.from(body)));
    return comandos.length.toString();
  }

  @override
  Future<void> disconnect({bool silent = false}) async {}
}

MotorControlController _duasPlacas(
  _ServicoFalso servico, {
  required String versaoQuadro,
}) {
  final MotorControlController c = MotorControlController(
    service: servico,
    loadSettings: false,
  )..isConnected = true;
  servico.onPayload?.call('iotmotor/esp32-01/status', 'online');
  servico.onPayload?.call('iotmotor/esp32-02/status', 'online');
  servico.onPayload?.call(
    'iotmotor/esp32-01/capabilities',
    jsonEncode(<String, String>{
      'device_id': 'esp32-01',
      'firmware_version': versaoQuadro,
    }),
  );
  servico.onPayload?.call(
    'iotmotor/esp32-02/capabilities',
    jsonEncode(<String, String>{
      'device_id': 'esp32-02',
      'firmware_version': firmwarePublicado[1],
    }),
  );
  return c;
}

void main() {
  test('perda de conexao e lida e gravada no quadro', () async {
    final _ServicoFalso servico = _ServicoFalso();
    final MotorControlController c = _duasPlacas(
      servico,
      versaoQuadro: firmwarePublicado[0],
    );
    addTearDown(c.dispose);
    servico.onPayload?.call(
      'iotmotor/esp32-01/telemetry',
      jsonEncode(<String, dynamic>{
        'device_id': 'esp32-01',
        'boot': '0123456789abcdef',
        'relays': <bool>[false, false, false, false],
        'voltage': 220,
        'pzem_ok': true,
        'link_grace_s': 10,
      }),
    );

    expect(c.linkGraceSeconds, 10);
    expect(await c.saveLinkGraceSeconds(-1), isTrue);
    expect(servico.comandos.single.$1, 'esp32-01');
    expect(servico.comandos.single.$2, 'link_grace');
    expect(servico.comandos.single.$3, <String, dynamic>{'seconds': -1});

    expect(await c.saveLinkGraceSeconds(3601), isFalse);
    expect(servico.comandos, hasLength(1));
  });

  test(
    'atualizar firmware vai para a placa desatualizada, no tópico dela',
    () async {
      final _ServicoFalso servico = _ServicoFalso();
      final MotorControlController c = _duasPlacas(
        servico,
        versaoQuadro: 'v16-desarme',
      );
      addTearDown(c.dispose);

      expect(c.maintenanceBoards, <String>['esp32-01', 'esp32-02']);
      expect(c.boardsToUpdate, <String>['esp32-01']);

      await c.sendMaintenanceCommand('update', c.boardsToUpdate);
      expect(servico.enviados, <(String, String?)>[('update', 'esp32-01')]);
      expect(
        servico.enviados.any(((String, String?) e) => e.$2 == 'auto'),
        isFalse,
      );
    },
  );

  test('placa fora do ar não recebe pedido de manutenção', () {
    final _ServicoFalso servico = _ServicoFalso();
    final MotorControlController c = _duasPlacas(
      servico,
      versaoQuadro: 'v16-desarme',
    );
    addTearDown(c.dispose);

    servico.onPayload?.call('iotmotor/esp32-01/status', 'offline');
    expect(c.maintenanceBoards, <String>['esp32-02']);
    expect(c.boardsToUpdate, isEmpty);
  });

  test(
    'placa sem status atual (só do histórico ou de outra conexão) fica de fora',
    () {
      final _ServicoFalso servico = _ServicoFalso();
      final MotorControlController c = _duasPlacas(
        servico,
        versaoQuadro: 'v16-desarme',
      );
      addTearDown(c.dispose);

      // Telemetria de uma placa que não anunciou status nesta conexão.
      servico.onPayload?.call('iotmotor/esp32-09/telemetry', '{"voltage":220}');
      expect(c.knownDeviceIds, contains('esp32-09'));
      expect(c.maintenanceBoards, <String>['esp32-01', 'esp32-02']);
      expect(c.boardsToUpdate, <String>['esp32-01']);
    },
  );

  test('confere as placas de novo na hora de enviar', () async {
    final _ServicoFalso servico = _ServicoFalso();
    final MotorControlController c = _duasPlacas(
      servico,
      versaoQuadro: 'v16-desarme',
    );
    addTearDown(c.dispose);
    final List<String> alvos = c.boardsToUpdate;

    // Enquanto o diálogo estava aberto, o quadro terminou de atualizar.
    servico.onPayload?.call(
      'iotmotor/esp32-01/capabilities',
      jsonEncode(<String, String>{
        'device_id': 'esp32-01',
        'firmware_version': firmwarePublicado[0],
      }),
    );
    await c.sendMaintenanceCommand('update', alvos);
    expect(servico.enviados, isEmpty);

    // E a rede própria não vai para placa que caiu nesse meio tempo.
    servico.onPayload?.call('iotmotor/esp32-02/status', 'offline');
    await c.sendMaintenanceCommand('wifi_portal', <String>['esp32-02']);
    expect(servico.enviados, isEmpty);
  });

  testWidgets('botão de firmware fica clicável e explica quando está em dia', (
    WidgetTester tester,
  ) async {
    final _ServicoFalso servico = _ServicoFalso();
    final MotorControlController c = _duasPlacas(
      servico,
      versaoQuadro: firmwarePublicado[0],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeviceMaintenanceSection(controller: c),
          ),
        ),
      ),
    );

    final OutlinedButton botao = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Atualizar firmware'),
    );
    expect(botao.onPressed, isNotNull);

    await tester.tap(find.text('Atualizar firmware'));
    await tester.pump();
    expect(
      find.text('O firmware das placas conectadas já está atualizado.'),
      findsOneWidget,
    );
    expect(servico.enviados, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('os botões únicos mandam para as placas certas', (
    WidgetTester tester,
  ) async {
    final _ServicoFalso servico = _ServicoFalso();
    final MotorControlController c = _duasPlacas(
      servico,
      versaoQuadro: 'v16-desarme',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeviceMaintenanceSection(controller: c),
          ),
        ),
      ),
    );

    // Atualizar firmware: um botão, só o quadro está desatualizado.
    await tester.tap(find.text('Atualizar firmware'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Vai atualizar: Quadro de comando.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(servico.enviados, <(String, String?)>[('update', 'esp32-01')]);

    // Cadastrar Wi-Fi: um botão, a placa é escolhida no diálogo.
    await tester.tap(find.text('Cadastrar Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('wifi_placa_esp32-02')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(servico.enviados.last, ('wifi_portal', 'esp32-02'));

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
