class MetricModel {
  final String id;
  final String name;
  final double value;
  final DateTime timestamp;

  MetricModel({
    required this.id,
    required this.name,
    required this.value,
    required this.timestamp,
  });

  factory MetricModel.fromJson(Map<String, dynamic> json) => MetricModel(
        id: json['id'] as String,
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
      };
}
