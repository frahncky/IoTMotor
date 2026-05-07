import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/settings_tab.dart';
import 'tabs/historico_tab.dart';
import 'tabs/inicio_tab.dart';
import 'widgets/delayed_reveal.dart';
import 'widgets/glass_panel.dart';

class MotorControlPage extends StatefulWidget {
  const MotorControlPage({super.key});

  @override
  State<MotorControlPage> createState() => _MotorControlPageState();
}

class _MotorControlPageState extends State<MotorControlPage> {
  late final MotorControlController _controller;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _controller = MotorControlController();
    _controller.addListener(_consumeControllerMessage);
  }

  @override
  void dispose() {
    _controller.removeListener(_consumeControllerMessage);
    _controller.dispose();
    super.dispose();
  }

  void _consumeControllerMessage() {
    final String? message = _controller.consumePendingMessage();
    if (message == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 76,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            backgroundColor: AppTheme.surfaceSoft,
            surfaceTintColor: Colors.transparent,
            title: Padding(
              padding: const EdgeInsets.fromLTRB(5, 8, 18, 8),
              child: _buildAppBarContent(),
            ),
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: _buildBottomNavigation(),
          ),
          body: Stack(
            children: <Widget>[
              _buildBackground(),
              SafeArea(
                top: false,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _buildCurrentTab(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackground() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(gradient: AppTheme.appBackgroundGradient),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSettingsMenu() {
    return PopupMenuButton<int>(
      tooltip: 'Navega\u00e7\u00e3o',
      icon: Icon(Icons.settings_rounded, color: AppTheme.brandBlue),
      onSelected: (int index) {
        setState(() {
          _selectedTab = index;
        });
      },
      itemBuilder:
          (BuildContext context) => const <PopupMenuEntry<int>>[
            PopupMenuItem<int>(
              value: 1,
              child: Row(
                children: <Widget>[
                  Icon(Icons.history_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Hist\u00f3rico'),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 2,
              child: Row(
                children: <Widget>[
                  Icon(Icons.settings_suggest_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Configura\u00e7\u00f5es'),
                ],
              ),
            ),
          ],
    );
  }

  Widget _buildCurrentTab() {
    switch (_selectedTab) {
      case 0:
        return InicioTab(controller: _controller);
      case 1:
        return HistoricoTab(controller: _controller);
      case 2:
        return ConfiguracoesTab(controller: _controller);
      default:
        return InicioTab(controller: _controller);
    }
  }

  Widget _buildAppBarContent() {
    final String tickerText =
        'Dispositivos conectados: ${_controller.connectedDevicesSummary} | '
        'Broker: ${_controller.brokerStatusLabel} | '
        'Alertas: ${_controller.alertStatusSummary} |';

    return DelayedReveal(
      delay: const Duration(milliseconds: 60),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Transform.scale(
                scale: 1.14,
                child: Image.asset(
                  'assets/logo/app_icon9.png',
                  fit: BoxFit.cover,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) {
                    return const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(Icons.device_hub_rounded),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.ink,
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
                        color: _statusColor(),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _NewsTicker(
                        text: tickerText,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          color: AppTheme.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor() {
    if (_controller.isConnected) {
      return AppTheme.brandMint;
    }
    return AppTheme.offline;
  }

  Widget _buildBottomNavigation() {
    return GlassPanel(
      radius: 24,
      tint: AppTheme.brandBlue,
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 4),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        height: 58,
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Configura\u00e7\u00f5es',
          ),
        ],
      ),
    );
  }
}

class _NewsTicker extends StatefulWidget {
  const _NewsTicker({required this.text, this.style});

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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _NewsTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller
        ..reset()
        ..repeat();
    }
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
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }

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
