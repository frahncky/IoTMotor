import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/iot_motor/models/mqtt_connection_config.dart';

class MqttProfileSummary {
  final String id;
  final String name;
  final String broker;
  final String topicPrefix;

  const MqttProfileSummary({
    required this.id,
    required this.name,
    required this.broker,
    required this.topicPrefix,
  });
}

class MqttProfile {
  final String id;
  final String name;
  final MqttConnectionConfig config;

  const MqttProfile({
    required this.id,
    required this.name,
    required this.config,
  });

  MqttProfile copyWith({
    String? id,
    String? name,
    MqttConnectionConfig? config,
  }) {
    return MqttProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'config': {
        'host': config.host,
        'port': config.port,
        'clientId': config.clientId,
        'topicPrefix': config.topicPrefix,
        'deviceId': config.deviceId,
        'useTls': config.useTls,
        'username': config.username,
        'password': config.password,
      },
    };
  }

  static MqttProfile fromMap(Map<String, dynamic> map) {
    final cfg = map['config'] as Map<String, dynamic>;
    return MqttProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      config: MqttConnectionConfig(
        host: cfg['host'] as String,
        port: cfg['port'] as int,
        clientId: cfg['clientId'] as String,
        topicPrefix: cfg['topicPrefix'] as String,
        deviceId: cfg['deviceId'] as String,
        useTls: cfg['useTls'] as bool,
        username: cfg['username'] as String?,
        password: cfg['password'] as String?,
      ),
    );
  }
}

class MqttProfilesNotifier extends StateNotifier<List<MqttProfile>> {
  static const _profilesKey = 'mqtt_profiles_v2';
  static const _activeProfileIdKey = 'mqtt_active_profile_id';

  MqttProfilesNotifier() : super([]) {
    load();
  }

  String? _activeProfileId;
  String? get activeProfileId => _activeProfileId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawProfiles = prefs.getString(_profilesKey);
    if (rawProfiles == null || rawProfiles.isEmpty) {
      // Cria perfil padrão
      final defaultProfile = MqttProfile(
        id: 'default',
        name: 'Dispositivo principal',
        config: MqttConnectionConfig(
          host: 'broker.hivemq.com',
          port: 1883,
          clientId: 'motor_app',
          topicPrefix: 'iotmotor',
          deviceId: 'default',
          useTls: false,
        ),
      );
      state = [defaultProfile];
      _activeProfileId = defaultProfile.id;
      await _persist();
      return;
    }
    final decoded = jsonDecode(rawProfiles) as List<dynamic>;
    state = decoded.map((e) => MqttProfile.fromMap(e as Map<String, dynamic>)).toList();
    _activeProfileId = prefs.getString(_activeProfileIdKey) ?? state.first.id;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilesKey, jsonEncode(state.map((e) => e.toMap()).toList()));
    if (_activeProfileId != null) {
      await prefs.setString(_activeProfileIdKey, _activeProfileId!);
    }
  }

  void setActiveProfile(String id) async {
    _activeProfileId = id;
    await _persist();
  }

  MqttProfile? get activeProfile =>
      state.firstWhere((p) => p.id == _activeProfileId, orElse: () => state.first);

  Future<void> addProfile(MqttProfile profile) async {
    state = [...state, profile];
    _activeProfileId = profile.id;
    await _persist();
  }

  Future<void> updateProfile(MqttProfile profile) async {
    state = [
      for (final p in state)
        if (p.id == profile.id) profile else p
    ];
    await _persist();
  }

  Future<void> deleteProfile(String id) async {
    if (state.length == 1) return;
    state = state.where((p) => p.id != id).toList();
    if (_activeProfileId == id) {
      _activeProfileId = state.first.id;
    }
    await _persist();
  }
}

final mqttProfilesProvider = StateNotifierProvider<MqttProfilesNotifier, List<MqttProfile>>(
  (ref) => MqttProfilesNotifier(),
);
