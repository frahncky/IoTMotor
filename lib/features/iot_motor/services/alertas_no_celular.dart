import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mqtt_connection_config.dart';
import 'alertas_da_bancada.dart';
import 'mqtt_motor_service.dart';

/// Alertas no celular: avisa quando um alarme da placa dispara, mesmo com o
/// app fechado.
///
/// Desligado por padrão. Ligado, roda um serviço do Android em primeiro plano
/// com a própria conexão MQTT (o Android exige a notificação fixa enquanto
/// ele roda) e volta sozinho depois de reiniciar o celular. Só Android.
class AlertasNoCelular {
  AlertasNoCelular._();

  static const String _chaveLigado = 'alertas_celular_ligado_v1';
  static const String _chaveConfig = 'alertas_celular_config_v1';
  static const String _eventoParar = 'alertas_parar';

  static const String canalAlarmes = 'iotmotor_alarmes';
  static const String canalServico = 'iotmotor_vigia';
  static const int idNotificacaoFixa = 7;

  static const FlutterSecureStorage _cofre = FlutterSecureStorage();

  static bool get suportado => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> ligado() async {
    if (!suportado) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveLigado) ?? false;
  }

  /// Liga os alertas com a conexão [config]. Devolve o motivo quando não dá
  /// (por exemplo, permissão de notificação negada); `null` quando ligou.
  static Future<String?> ligar(MqttConnectionConfig config) async {
    if (!suportado) return 'Os alertas no celular existem só no Android.';
    final FlutterLocalNotificationsPlugin notificacoes = FlutterLocalNotificationsPlugin();
    await _prepararNotificacoes(notificacoes);
    final AndroidFlutterLocalNotificationsPlugin? android = notificacoes
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final bool permitido = await android?.requestNotificationsPermission() ?? false;
    if (!permitido) {
      return 'Sem permissão para notificações: libere nas configurações do Android.';
    }
    await _guardarConfig(config);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveLigado, true);
    await _reiniciarServico();
    return null;
  }

  static Future<void> desligar() async {
    if (!suportado) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveLigado, false);
    final FlutterBackgroundService servico = FlutterBackgroundService();
    // Sem isto o Android o iniciaria de novo no boot (ele se desligaria ao ver
    // a opção desligada, mas a notificação fixa piscaria).
    await _configurarServico(servico, noBoot: false);
    if (await servico.isRunning()) servico.invoke(_eventoParar);
  }

  /// Nova conexão no app (outro broker, outro prefixo): o serviço acompanha.
  static Future<void> atualizarConexao(MqttConnectionConfig config) async {
    if (!await ligado()) return;
    final String? antes = await _cofre.read(key: _chaveConfig);
    await _guardarConfig(config);
    if (antes != await _cofre.read(key: _chaveConfig)) await _reiniciarServico();
  }

  /// Ao abrir o app: se estava ligado e o serviço parou (o sistema matou, o
  /// app foi atualizado), volta a rodar.
  static Future<void> garantirAoAbrir() async {
    if (!await ligado()) return;
    if (await _lerConfig() == null) return;
    final FlutterBackgroundService servico = FlutterBackgroundService();
    await _configurarServico(servico);
    if (!await servico.isRunning()) await servico.startService();
  }

  static Future<void> _reiniciarServico() async {
    final FlutterBackgroundService servico = FlutterBackgroundService();
    await _configurarServico(servico);
    if (await servico.isRunning()) {
      servico.invoke(_eventoParar);
      for (int i = 0; i < 20 && await servico.isRunning(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    await servico.startService();
  }

  static Future<void> _configurarServico(FlutterBackgroundService servico, {bool noBoot = true}) async {
    await _prepararNotificacoes(FlutterLocalNotificationsPlugin());
    await servico.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _vigiar,
        autoStart: false,
        autoStartOnBoot: noBoot,
        isForegroundMode: true,
        notificationChannelId: canalServico,
        initialNotificationTitle: 'IoTMotor: alertas ligados',
        initialNotificationContent: 'Conectando ao broker…',
        foregroundServiceNotificationId: idNotificacaoFixa,
        // specialUse: dataSync no Android 15 cai após 6 h por dia e não pode
        // voltar no boot.
        foregroundServiceTypes: <AndroidForegroundType>[AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> _prepararNotificacoes(FlutterLocalNotificationsPlugin notificacoes) async {
    await notificacoes.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final AndroidFlutterLocalNotificationsPlugin? android = notificacoes
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      canalAlarmes,
      'Alarmes da bancada',
      description: 'Um alarme da placa disparou ou voltou ao normal.',
      importance: Importance.high,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      canalServico,
      'Vigia dos alarmes',
      description: 'Notificação fixa enquanto os alertas estão ligados.',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));
  }

  static Future<void> _guardarConfig(MqttConnectionConfig c) async {
    await _cofre.write(
      key: _chaveConfig,
      value: jsonEncode(<String, dynamic>{
        'host': c.host,
        'port': c.port,
        'clientId': c.clientId,
        'topicPrefix': c.topicPrefix,
        'useTls': c.useTls,
        'username': c.username,
        'password': c.password,
      }),
    );
  }

  static Future<MqttConnectionConfig?> _lerConfig() async {
    try {
      final String? texto = await _cofre.read(key: _chaveConfig);
      if (texto == null) return null;
      final Map<String, dynamic> m = jsonDecode(texto) as Map<String, dynamic>;
      return MqttConnectionConfig(
        host: m['host'] as String,
        port: m['port'] as int,
        clientId: m['clientId'] as String,
        topicPrefix: m['topicPrefix'] as String,
        deviceId: 'auto',
        useTls: m['useTls'] as bool,
        username: m['username'] as String?,
        password: m['password'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Serviço em primeiro plano: conecta, escuta e avisa.
@pragma('vm:entry-point')
Future<void> _vigiar(ServiceInstance servico) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final MqttConnectionConfig? config = await AlertasNoCelular._lerConfig();
  if (!(prefs.getBool(AlertasNoCelular._chaveLigado) ?? false) || config == null) {
    await servico.stopSelf();
    return;
  }

  final FlutterLocalNotificationsPlugin notificacoes = FlutterLocalNotificationsPlugin();
  await AlertasNoCelular._prepararNotificacoes(notificacoes);
  final AlertasDaBancada alertas = AlertasDaBancada();

  MqttServerClient? cliente;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? mensagens;
  Timer? tentarDeNovo;
  bool parando = false;

  void estado(String texto) {
    if (servico is AndroidServiceInstance) {
      servico.setForegroundNotificationInfo(title: 'IoTMotor: alertas ligados', content: texto);
    }
  }

  Future<void> mostrar(AvisoDoCelular aviso) => notificacoes.show(
        id: aviso.id,
        title: aviso.titulo,
        body: aviso.texto,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            AlertasNoCelular.canalAlarmes,
            'Alarmes da bancada',
            importance: Importance.high,
            priority: Priority.high,
            silent: !aviso.comSom,
            category: AndroidNotificationCategory.alarm,
            ticker: aviso.titulo,
          ),
        ),
      );

  Future<void> conectar() async {
    if (parando) return;
    try {
      final MqttServerClient c =
          await MqttMotorService.criarCliente(config, clientId: '${config.clientId}_alertas');
      c.onAutoReconnect = () => estado('Sem conexão com o broker; tentando de novo…');
      c.onAutoReconnected = () => estado('Vigiando os alarmes da bancada');
      await c.connect(config.username, config.password);
      if (c.connectionStatus?.state != MqttConnectionState.connected) throw StateError('recusado');
      cliente = c;
      c.subscribe('${config.topicPrefix}/+/alarms', MqttQos.atMostOnce);
      c.subscribe('${config.topicPrefix}/+/telemetry', MqttQos.atMostOnce);
      mensagens = c.updates?.listen((List<MqttReceivedMessage<MqttMessage>> pacotes) {
        for (final MqttReceivedMessage<MqttMessage> pacote in pacotes) {
          final MqttPublishMessage m = pacote.payload as MqttPublishMessage;
          final String texto = MqttPublishPayload.bytesToStringAsString(m.payload.message);
          for (final AvisoDoCelular aviso in alertas.receber(pacote.topic, texto)) {
            unawaited(mostrar(aviso));
          }
        }
      });
      estado('Vigiando os alarmes da bancada');
    } catch (_) {
      // Sem rede ou broker fora: tenta de novo daqui a pouco, sem desistir.
      estado('Sem conexão com o broker; tentando de novo…');
      tentarDeNovo = Timer(const Duration(seconds: 30), () => unawaited(conectar()));
    }
  }

  servico.on(AlertasNoCelular._eventoParar).listen((_) async {
    parando = true;
    tentarDeNovo?.cancel();
    await mensagens?.cancel();
    cliente?.autoReconnect = false;
    cliente?.disconnect();
    await servico.stopSelf();
  });

  await conectar();
}
