part of 'inicio_tab.dart';

/// Grandezas e gráficos da aba Início: grupos, curvas e escolha de cada gráfico.
extension _InicioGraficos on _InicioTabState {
  Widget _buildChartsPanel(
    BuildContext context, {
    required TelemetrySample? sample,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        final double rawHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 620;
        if (_selectedGroup == _TelemetryGroup.grandezas) {
          return _buildGrandezasPanel(constraints);
        }

        final List<_TelemetryPlot> plots = _plotsForGroup(_selectedGroup);
        final String selectedPlotAId = _selectedPlotAId;
        final String selectedPlotBId = _selectedPlotBId;
        final _TelemetryPlot plotA = _plotById(selectedPlotAId, plots);
        final _TelemetryPlot plotB = _plotById(selectedPlotBId, plots);

        if (wide) {
          final double availableForCards = (rawHeight - 54).clamp(
            260.0,
            1200.0,
          );
          final double cardHeight = availableForCards.clamp(220.0, 420.0);
          final double plotHeight = (cardHeight - 86).clamp(84.0, 320.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildGroupSelector(),
              const SizedBox(height: 8),
              SizedBox(
                height: cardHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _buildChartForPlot(
                        context,
                        plotA,
                        sample,
                        plotHeight,
                        selectedPlotId: selectedPlotAId,
                        plots: plots,
                        onPlotChanged: _setSelectedPlotAId,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildChartForPlot(
                        context,
                        plotB,
                        sample,
                        plotHeight,
                        selectedPlotId: selectedPlotBId,
                        plots: plots,
                        onPlotChanged: _setSelectedPlotBId,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final double availableForCards = (rawHeight - 54).clamp(260.0, 1200.0);
        final double cardHeight = ((availableForCards - 10) / 2).clamp(
          150.0,
          360.0,
        );
        final double plotHeight = (cardHeight - 86).clamp(72.0, 250.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildGroupSelector(),
            const SizedBox(height: 8),
            SizedBox(
              height: cardHeight,
              child: _buildChartForPlot(
                context,
                plotA,
                sample,
                plotHeight,
                selectedPlotId: selectedPlotAId,
                plots: plots,
                onPlotChanged: _setSelectedPlotAId,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: cardHeight,
              child: _buildChartForPlot(
                context,
                plotB,
                sample,
                plotHeight,
                selectedPlotId: selectedPlotBId,
                plots: plots,
                onPlotChanged: _setSelectedPlotBId,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrandezasPanel(BoxConstraints constraints) {
    final Widget panel = GrandezasTab(
      controller: widget.controller,
      showHeader: false,
      padding: EdgeInsets.zero,
    );

    if (!constraints.maxHeight.isFinite) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildGroupSelector(),
          const SizedBox(height: 8),
          // Mantém o painel compacto; o grid adapta a altura dos cards.
          SizedBox(
            height: constraints.maxWidth >= 760 ? 172 : 360,
            child: panel,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildGroupSelector(),
        const SizedBox(height: 8),
        Expanded(child: panel),
      ],
    );
  }

  Widget _buildGroupSelector() {
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_TelemetryGroup>(
          showSelectedIcon: false,
          selected: <_TelemetryGroup>{_selectedGroup},
          onSelectionChanged: (Set<_TelemetryGroup> selection) {
            widget.controller.setDashboardTab(
              _dashboardTabForGroup(selection.first),
            );
          },
          segments: const <ButtonSegment<_TelemetryGroup>>[
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.grandezas,
              icon: Icon(Icons.speed_rounded, size: 16),
              label: Text('Medições'),
            ),
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.eletrica,
              icon: Icon(Icons.electric_bolt_rounded, size: 16),
              label: Text('Elétrica'),
            ),
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.mecanica,
              icon: Icon(Icons.sensors_rounded, size: 16),
              label: Text('Mecânica'),
            ),
          ],
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: const WidgetStatePropertyAll<EdgeInsets>(
              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            textStyle: const WidgetStatePropertyAll<TextStyle>(
              TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  String get _selectedPlotAId {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        return widget.controller.electricalPlotAId;
      case _TelemetryGroup.eletrica:
        return widget.controller.electricalPlotAId;
      case _TelemetryGroup.mecanica:
        return widget.controller.mechanicalPlotAId;
    }
  }

  String get _selectedPlotBId {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        return widget.controller.electricalPlotBId;
      case _TelemetryGroup.eletrica:
        return widget.controller.electricalPlotBId;
      case _TelemetryGroup.mecanica:
        return widget.controller.mechanicalPlotBId;
    }
  }

  void _setSelectedPlotAId(String id) {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        widget.controller.setElectricalPlotAId(id);
        break;
      case _TelemetryGroup.eletrica:
        widget.controller.setElectricalPlotAId(id);
        break;
      case _TelemetryGroup.mecanica:
        widget.controller.setMechanicalPlotAId(id);
        break;
    }
  }

  void _setSelectedPlotBId(String id) {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        widget.controller.setElectricalPlotBId(id);
        break;
      case _TelemetryGroup.eletrica:
        widget.controller.setElectricalPlotBId(id);
        break;
      case _TelemetryGroup.mecanica:
        widget.controller.setMechanicalPlotBId(id);
        break;
    }
  }

  Widget _buildChartForPlot(
    BuildContext context,
    _TelemetryPlot plot,
    TelemetrySample? sample,
    double plotHeight, {
    required String selectedPlotId,
    required List<_TelemetryPlot> plots,
    required ValueChanged<String> onPlotChanged,
  }) {
    final bool connected = widget.controller.isConnected;
    final bool recebeuDadoAtual = widget.controller.recebeuDadoAtual;
    final List<double> values = _seriesForPlot(plot);
    // Só mostra valores se já recebeu dado novo na sessão atual
    final List<double> sessionValues =
        (connected && recebeuDadoAtual) ? values : <double>[];
    return TelemetryChart(
      title: plot.title,
      color: plot.color,
      values: sessionValues,
      unit: plot.unit,
      instantValue:
          (connected && recebeuDadoAtual && sample != null)
              ? plot.readValue(sample)
              : null,
      decimalDigits: plot.decimalDigits,
      chartHeight: plotHeight,
      titleWidget: _buildPlotTitleMenu(
        context,
        plot: plot,
        selectedPlotId: selectedPlotId,
        plots: plots,
        onPlotChanged: onPlotChanged,
      ),
    );
  }

  Widget _buildPlotTitleMenu(
    BuildContext context, {
    required _TelemetryPlot plot,
    required String selectedPlotId,
    required List<_TelemetryPlot> plots,
    required ValueChanged<String> onPlotChanged,
  }) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String titleText =
        plot.unit.isEmpty ? plot.title : '${plot.title} (${plot.unit})';

    return Builder(
      builder: (BuildContext titleContext) {
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            _openPlotMenu(
              titleContext,
              selectedPlotId: selectedPlotId,
              plots: plots,
              onPlotChanged: onPlotChanged,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down_rounded, color: plot.color, size: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPlotMenu(
    BuildContext context, {
    required String selectedPlotId,
    required List<_TelemetryPlot> plots,
    required ValueChanged<String> onPlotChanged,
  }) async {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final double menuWidth =
        overlay.size.width < 260 ? overlay.size.width - 16 : 240;
    final double maxLeft = overlay.size.width - menuWidth - 8;
    final double left = topLeft.dx.clamp(8.0, maxLeft).toDouble();
    final double top =
        (topLeft.dy + button.size.height + 4)
            .clamp(8.0, overlay.size.height - 8)
            .toDouble();

    final String? selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - menuWidth,
        0,
      ),
      items:
          plots.map((_TelemetryPlot option) {
            final bool selected = option.id == selectedPlotId;
            return PopupMenuItem<String>(
              value: option.id,
              child: Row(
                children: <Widget>[
                  Icon(Icons.show_chart_rounded, color: option.color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_rounded,
                      color: AppTheme.brandMint,
                      size: 18,
                    ),
                ],
              ),
            );
          }).toList(),
    );

    if (!mounted || selected == null) {
      return;
    }
    onPlotChanged(selected);
  }

  List<double> _seriesForPlot(_TelemetryPlot plot) {
    return widget.controller.history
        .map((TelemetrySample sample) => plot.readValue(sample))
        .whereType<double>()
        .toList();
  }

  _TelemetryGroup _groupFromDashboardTab(String value) {
    switch (value) {
      case MotorControlController.dashboardTabElectrical:
        return _TelemetryGroup.eletrica;
      case MotorControlController.dashboardTabMechanical:
        return _TelemetryGroup.mecanica;
      case MotorControlController.dashboardTabMeasurements:
      default:
        return _TelemetryGroup.grandezas;
    }
  }

  String _dashboardTabForGroup(_TelemetryGroup group) {
    switch (group) {
      case _TelemetryGroup.grandezas:
        return MotorControlController.dashboardTabMeasurements;
      case _TelemetryGroup.eletrica:
        return MotorControlController.dashboardTabElectrical;
      case _TelemetryGroup.mecanica:
        return MotorControlController.dashboardTabMechanical;
    }
  }

  List<_TelemetryPlot> _plotsForGroup(_TelemetryGroup group) {
    return _telemetryPlots
        .where((_TelemetryPlot plot) => plot.group == group)
        .toList();
  }

  _TelemetryPlot _plotById(String id, List<_TelemetryPlot> plots) {
    return plots.firstWhere(
      (_TelemetryPlot plot) => plot.id == id,
      orElse: () => plots.first,
    );
  }
}
