import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';
import 'package:iotmotor/features/iot_motor/services/firmware_publicado_service.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';

/// A versão publicada vem do firmware-latest.json do CI: um firmware novo
/// aparece como atualização sem precisar de app novo.
void main() {
  test('lê o JSON do CI e recusa conteúdo estranho', () {
    expect(
      lerFirmwarePublicado(<String, Object>{
        'v': 1,
        'esp32-01': 'v30-x',
        'esp32-02': 's3-sensors-2.0',
      }),
      <String>['v30-x', 's3-sensors-2.0'],
    );
    expect(lerFirmwarePublicado(<String, Object>{'esp32-01': 'v30'}), isNull);
    expect(
      lerFirmwarePublicado(<String, Object>{
        'esp32-01': '<script>',
        'esp32-02': 'ok',
      }),
      isNull,
    );
    expect(lerFirmwarePublicado('texto'), isNull);
  });

  test('tenta a ponte da Cloudflare e, se falhar, o GitHub', () async {
    final List<String> pedidos = <String>[];
    final FirmwarePublicadoService servico = FirmwarePublicadoService(
      client: MockClient((http.Request pedido) async {
        pedidos.add(pedido.url.host);
        if (pedido.url.host == 'iotmotor.pages.dev') {
          return http.Response('erro', 502);
        }
        return http.Response('{"esp32-01":"v31","esp32-02":"s3-3"}', 200);
      }),
    );
    expect(await servico.buscar(), <String>['v31', 's3-3']);
    expect(pedidos, <String>['iotmotor.pages.dev', 'github.com']);
  });

  test('sem nenhum endereço, devolve null (fica a reserva)', () async {
    final FirmwarePublicadoService servico = FirmwarePublicadoService(
      client: MockClient((_) async => throw Exception('sem rede')),
    );
    expect(await servico.buscar(), isNull);
  });

  test('ao conectar, o app passa a comparar com a versão publicada', () async {
    final _MqttFalso mqtt = _MqttFalso();
    final MotorControlController c = MotorControlController(
      service: mqtt,
      loadSettings: false,
      firmwarePublicadoService: FirmwarePublicadoService(
        client: MockClient(
          (_) async =>
              http.Response('{"esp32-01":"v99-novo","esp32-02":"s3-9"}', 200),
        ),
      ),
    );
    addTearDown(c.dispose);
    expect(c.publishedFirmware, firmwarePublicado); // Antes: a reserva.

    mqtt.onConnected?.call();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.publishedFirmware, <String>['v99-novo', 's3-9']);

    c.handlePayloadForTest(
      'iotmotor/esp32-01/capabilities',
      '{"device_id":"esp32-01","firmware_version":"v99-novo"}',
    );
    expect(c.firmwareOf('esp32-01')?.atualizar, isFalse);
    c.handlePayloadForTest(
      'iotmotor/esp32-01/capabilities',
      '{"device_id":"esp32-01","firmware_version":"${firmwarePublicado[0]}"}',
    );
    expect(c.firmwareOf('esp32-01')?.atualizar, isTrue);
  });
}

class _MqttFalso extends MqttMotorService {
  @override
  Future<void> disconnect({bool silent = false}) async {}
}
