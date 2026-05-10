import 'metric_model.dart';

class MetricRepository {
  final List<MetricModel> _metrics = [];

  void addMetric(MetricModel metric) {
    _metrics.add(metric);
  }

  List<MetricModel> getAll() => List.unmodifiable(_metrics);

  MetricModel? getById(String id) => _metrics.firstWhere(
        (m) => m.id == id,
        orElse: () => throw Exception('Metric not found'),
      );
}
