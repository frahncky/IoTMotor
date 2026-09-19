import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/iot_motor/controller/motor_control_controller.dart';
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

class MqttProfilesState {
  final List<MqttProfile> profiles;
  final String? activeProfileId;

  const MqttProfilesState({required this.profiles, this.activeProfileId});
}

class MqttProfilesNotifier extends StateNotifier<MqttProfilesState> {
  static const _profilesKey = 'mqtt_profiles_v2';
  static const _activeProfileIdKey = 'mqtt_active_profile_id';
  static const MqttProfile _defaultProfile = MqttProfile(
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
  static const MqttProfilesState _defaultState = MqttProfilesState(
    profiles: <MqttProfile>[_defaultProfile],
    activeProfileId: 'default',
  );

  final _secureStorage = const FlutterSecureStorage();

  MqttProfilesNotifier() : super(_defaultState) {
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawProfiles = await _secureStorage.read(key: _profilesKey);
      if (rawProfiles == null || rawProfiles.isEmpty) {
        state = _defaultState;
        await _persist();
        return;
      }

      final decoded = jsonDecode(rawProfiles) as List<dynamic>;
      final profiles =
          decoded
              .map((e) => MqttProfile.fromMap(e as Map<String, dynamic>))
              .toList();
      if (profiles.isEmpty) {
        state = _defaultState;
        await _persist();
        return;
      }

      final savedActiveId = prefs.getString(_activeProfileIdKey);
      final activeId =
          profiles.any((p) => p.id == savedActiveId)
              ? savedActiveId
              : profiles.first.id;
      state = MqttProfilesState(profiles: profiles, activeProfileId: activeId);
    } catch (_) {
      state = _defaultState;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(
      key: _profilesKey,
      value: jsonEncode(state.profiles.map((e) => e.toMap()).toList()),
    );
    if (state.activeProfileId != null) {
      await prefs.setString(_activeProfileIdKey, state.activeProfileId!);
    }
  }

  void setActiveProfile(String id) async {
    if (state.activeProfileId == id) return;
    state = MqttProfilesState(profiles: state.profiles, activeProfileId: id);
    await _persist();
  }

  MqttProfile? get activeProfile =>
      state.profiles.isEmpty
          ? null
          : state.profiles.firstWhere(
            (p) => p.id == state.activeProfileId,
            orElse: () => state.profiles.first,
          );

  Future<void> addProfile(MqttProfile profile) async {
    state = MqttProfilesState(
      profiles: [...state.profiles, profile],
      activeProfileId: profile.id,
    );
    await _persist();
  }

  Future<void> updateProfile(MqttProfile profile) async {
    final updatedList = [
      for (final p in state.profiles)
        if (p.id == profile.id) profile else p,
    ];
    state = MqttProfilesState(
      profiles: updatedList,
      activeProfileId: state.activeProfileId,
    );
    await _persist();
  }

  Future<void> deleteProfile(String id) async {
    if (state.profiles.length == 1) return;
    final updatedList = state.profiles.where((p) => p.id != id).toList();
    String? nextId = state.activeProfileId;
    if (state.activeProfileId == id) {
      nextId = updatedList.first.id;
    }
    state = MqttProfilesState(profiles: updatedList, activeProfileId: nextId);
    await _persist();
  }
}

final mqttProfilesProvider =
    StateNotifierProvider<MqttProfilesNotifier, MqttProfilesState>(
      (ref) => MqttProfilesNotifier(),
    );

final motorControlControllerProvider =
    ChangeNotifierProvider<MotorControlController>((ref) {
      final profilesState = ref.watch(mqttProfilesProvider);
      final activeId = profilesState.activeProfileId;

      if (profilesState.profiles.isEmpty) {
        throw Exception('Nenhum perfil disponível');
      }

      final activeProfile = profilesState.profiles.firstWhere(
        (p) => p.id == activeId,
        orElse: () => profilesState.profiles.first,
      );

      return MotorControlController.withMqttConfig(
        activeProfile.config,
        profileId: activeProfile.id,
      );
    });
