import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/board_history_panel.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/motor_usage_strip.dart';

void main() {
  testWidgets('dados do motor, uso, manutenção, firmware e histórico chegam pela placa', (WidgetTester tester) async {
    final _FakeMqttMotorService service = _FakeMqttMotorService();
    final MotorControlController controller = MotorControlController(service: service);
    service.config = const MqttConnectionConfig(
      host: 'broker', port: 1883, clientId: 't', topicPrefix: 'iotmotor', deviceId: 'auto', useTls: false,
    );
    controller.isConnected = true;

    service.emit('iotmotor/esp32-01/motor_info',
        '{"device_id":"esp32-01","current_a":12.6,"current_y_a":7.3,"voltage_v":220,"voltage_y_v":380,'
        '"phases":3,"connection":"delta","rpm":1730,"power_cv":5,"maint_interval_h":2000,"maint_done_run_s":0}');
    service.emit('iotmotor/esp32-01/capabilities', '{"device_id":"esp32-01","firmware_version":"v11-velho"}');
    service.emit('iotmotor/esp32-02/capabilities',
        '{"device_id":"esp32-02","firmware_version":"${firmwarePublicado[1]}"}');
    service.emit('iotmotor/esp32-01/telemetry',
        '{"device_id":"esp32-01","relays":[true,false,true,false],"current":6.3,"voltage":220,'
        '"run_s_total":7560000,"starts_today":3,"session_s":725}');
    service.emit('iotmotor/esp32-02/telemetry', '{"device_id":"esp32-02","vibration":0.03,"temperature":31}');
    final int hoje = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
    service.emit('iotmotor/esp32-02/history/${hoje % 7}',
        '{"device_id":"esp32-02","day":$hoje,"v":1,"hours":[[0,912,1034,2201,452,480,31,55,45]]}');

    expect(controller.motorInfo?.currentInUse, 12.6);
    expect(controller.motorUsage?.startsToday, 3);
    expect(controller.maintenanceStatus?.vencida, isTrue);  // 2100 h de uso com intervalo de 2000 h.
    expect(controller.alerts.any((a) => a.metric == 'manutencao'), isTrue);
    expect(controller.firmwareOf('esp32-01')?.atualizar, isTrue);
    expect(controller.firmwareOf('esp32-02')?.atualizar, isFalse);
    expect(controller.boardHistory, hasLength(1));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: <Widget>[
            MotorUsageStrip(controller: controller),
            BoardHistoryPanel(horas: controller.boardHistory),
          ]),
        ),
      ),
    ));
    expect(find.text('Carga 50%'), findsOneWidget);
    expect(find.textContaining('mm/s · Aceitável'), findsOneWidget);
    expect(find.textContaining('Horímetro 2100,0 h · 3 partidas hoje'), findsOneWidget);
    expect(find.textContaining('Manutenção vencida há 100 h'), findsOneWidget);
    expect(find.textContaining('Quadro de comando: firmware v11-velho'), findsOneWidget);
    expect(find.textContaining('Motor ligado 0 h 45 min em 7 dias'), findsOneWidget);
    await tester.tap(find.text('Temperatura'));
    await tester.pump();

    controller.dispose();
  });
}

class _FakeMqttMotorService extends MqttMotorService {
  MqttConnectionConfig? config;

  @override
  MqttConnectionConfig? get activeConfig => config;

  void emit(String topic, String payload) => onPayload?.call(topic, payload);

  @override
  Future<void> disconnect({bool silent = false}) async {}
}
