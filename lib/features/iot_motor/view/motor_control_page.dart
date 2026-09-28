import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:iotmotor/app/theme/app_theme.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/alertas_no_celular.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/settings_tab.dart';
import 'package:iotmotor/app/providers/mqtt_profiles_provider.dart';
import 'package:iotmotor/app/providers/motor_sound_provider.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/alertas_tab.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/historico_tab.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/inicio_tab.dart';

class MotorControlPage extends ConsumerStatefulWidget {
  const MotorControlPage({super.key});

  @override
  ConsumerState<MotorControlPage> createState() => _MotorControlPageState();
}

class _MotorControlPageState extends ConsumerState<MotorControlPage>
    with WidgetsBindingObserver {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(motorSoundServiceProvider).setForeground(true));
    // Alertas no celular ligados e o serviço parado (o sistema matou, o app
    // foi atualizado): volta a vigiar.
    unawaited(AlertasNoCelular.garantirAoAbrir());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool foreground = state == AppLifecycleState.resumed;
    final sound = ref.read(motorSoundServiceProvider);
    unawaited(sound.setForeground(foreground));

    if (foreground) {
      final controller = ref.read(motorControlControllerProvider);
      unawaited(
        sound.syncConfirmedState(
          connected: controller.isConnected,
          hasConfirmedState: controller.benchRelays != null,
          motorOn: controller.isMotorRunning,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(motorControlControllerProvider);
    final motorSound = ref.watch(motorSoundServiceProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        motorSound.syncConfirmedState(
          connected: controller.isConnected,
          hasConfirmedState: controller.benchRelays != null,
          motorOn: controller.isMotorRunning,
        ),
      );
    });

    // Escuta mensagens pendentes (SnackBars) vindas do controller
    ref.listen<MotorControlController>(motorControlControllerProvider, (
      previous,
      next,
    ) {
      // Conectou (talvez em outro broker): os alertas seguem a mesma conexão.
      final MqttConnectionConfig? conexao = next.activeConnectionConfig;
      if (next.isConnected &&
          !(previous?.isConnected ?? false) &&
          conexao != null) {
        unawaited(AlertasNoCelular.atualizarConexao(conexao));
      }
      unawaited(
        ref
            .read(motorSoundServiceProvider)
            .syncConfirmedState(
              connected: next.isConnected,
              hasConfirmedState: next.benchRelays != null,
              motorOn: next.isMotorRunning,
            ),
      );

      final message = next.consumePendingMessage();
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.surfaceSoft,
        surfaceTintColor: Colors.transparent,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(5, 8, 18, 8),
          child: _buildAppBarContent(controller),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
      body: Stack(
        children: <Widget>[
          _buildBackground(),
          SafeArea(
            top: false,
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedTab),
              child: _buildCurrentTab(controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(gradient: AppTheme.appBackgroundGradient),
      ),
    );
  }

  Widget _buildCurrentTab(MotorControlController controller) {
    switch (_selectedTab) {
      case 0:
        return InicioTab(controller: controller);
      case 1:
        return HistoricoTab(controller: controller);
      case 2:
        return AlertasTab(controller: controller);
      case 3:
        return ConfiguracoesTab(controller: controller);
      default:
        return InicioTab(controller: controller);
    }
  }

  Widget _buildAppBarContent(MotorControlController controller) {
    final TextTheme texto = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 36,
          height: 36,
          child: Image.asset(
            'assets/logo/app_icon9.png',
            fit: BoxFit.contain,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                    const Icon(Icons.device_hub_rounded),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              RichText(
                text: TextSpan(
                  style: texto.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'IoT',
                      style: TextStyle(color: AppTheme.brandMint),
                    ),
                    const TextSpan(text: 'Motor'),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(controller),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _NewsTicker(
                      key: const ValueKey<String>('app_bar_status'),
                      text: _tickerText(controller),
                      style: texto.labelMedium?.copyWith(
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Resumo curto do topo: sistema, as duas placas e clientes conectados.
  String _tickerText(MotorControlController controller) {
    final List<String> conectadas = controller.connectedDeviceIds;
    final bool comandos = conectadas.contains('esp32-01');
    final bool sensores = conectadas.contains('esp32-02');
    final String sistema =
        !controller.isConnected
            ? (controller.isBusy ? 'Conectando' : 'Offline')
            : controller.hasStaleTelemetry || !comandos || !sensores
            ? 'Atenção'
            : 'Online';
    final String clientes = controller.commandClientsSummary
        .split(' · ')
        .skip(1)
        .join(' · ');
    return 'Sistema: $sistema   •   '
        'Dispositivos: Comandos ${comandos ? 'online' : 'offline'} · '
        'Sensores ${sensores ? 'online' : 'offline'}   •   '
        'Clientes: $clientes';
  }

  Color _statusColor(MotorControlController controller) {
    if (controller.hasStaleTelemetry) {
      return AppTheme.brandOrange;
    }
    if (controller.isConnected) {
      return AppTheme.brandMint;
    }
    return AppTheme.offline;
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      backgroundColor: AppTheme.surfaceSoft,
      height: 64,
      elevation: 0,
      selectedIndex: _selectedTab,
      onDestinationSelected: (int index) {
        setState(() {
          _selectedTab = index;
        });
      },
      destinations: const <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'In\u00edcio',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history_rounded),
          label: 'Hist\u00f3rico',
        ),
        NavigationDestination(
          icon: Icon(Icons.notification_important_outlined),
          selectedIcon: Icon(Icons.notification_important_rounded),
          label: 'Alertas',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Configura\u00e7\u00f5es',
        ),
      ],
    );
  }
}

/// Linha de informações que corre da direita para a esquerda quando não cabe
/// na largura; se couber, fica parada.
class _NewsTicker extends StatefulWidget {
  const _NewsTicker({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_NewsTicker> createState() => _NewsTickerState();
}

class _NewsTickerState extends State<_NewsTicker>
    with SingleTickerProviderStateMixin {
  static const double _gap = 28;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Só anda quando o texto não cabe (ver _rolar): parado, não pede quadros.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
  }

  /// Liga ou desliga a animação depois do quadro atual, sem mexer nela
  /// durante o build.
  void _rolar(bool rolar) {
    if (rolar == _controller.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || rolar == _controller.isAnimating) return;
      if (rolar) {
        _controller.repeat();
      } else {
        _controller
          ..stop()
          ..value = 0;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style =
        widget.style ??
        Theme.of(context).textTheme.labelMedium ??
        const TextStyle();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) {
          _rolar(false);
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }

        final double cycleWidth = painter.width + _gap;
        if (cycleWidth <= constraints.maxWidth) {
          _rolar(false);
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }

        _rolar(true);
        return ClipRect(
          child: SizedBox(
            width: constraints.maxWidth,
            height: painter.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                final double offset = -_controller.value * cycleWidth;
                return Stack(
                  children: <Widget>[
                    Positioned(
                      left: offset,
                      top: 0,
                      child: Text(
                        widget.text,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                    Positioned(
                      left: offset + cycleWidth,
                      top: 0,
                      child: Text(
                        widget.text,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
