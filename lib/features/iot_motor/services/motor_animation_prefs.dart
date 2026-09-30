import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Efeitos do desenho do motor, escolhidos em Configurações › Motor.
///
/// Os mesmos do painel web (Configurações › Animação e som do motor). Tudo
/// ligado por padrão; "reduzir movimento" do sistema continua valendo por cima.
@immutable
class MotorAnimationEffects {
  const MotorAnimationEffects({
    this.giro = true,
    this.tremor = true,
    this.calor = true,
    this.alarme = true,
  });

  /// Girar na partida, no regime e na parada por inércia.
  final bool giro;

  /// Tremer com a vibração nas zonas Alerta e Crítica.
  final bool tremor;

  /// Mudar de cor conforme a temperatura se aproxima do limite.
  final bool calor;

  /// Piscar os ícones de alarme.
  final bool alarme;

  MotorAnimationEffects copyWith({
    bool? giro,
    bool? tremor,
    bool? calor,
    bool? alarme,
  }) => MotorAnimationEffects(
    giro: giro ?? this.giro,
    tremor: tremor ?? this.tremor,
    calor: calor ?? this.calor,
    alarme: alarme ?? this.alarme,
  );

  @override
  bool operator ==(Object other) =>
      other is MotorAnimationEffects &&
      other.giro == giro &&
      other.tremor == tremor &&
      other.calor == calor &&
      other.alarme == alarme;

  @override
  int get hashCode => Object.hash(giro, tremor, calor, alarme);
}

/// Guarda os efeitos neste aparelho, como o som do motor.
class MotorAnimationPrefs extends ChangeNotifier {
  MotorAnimationPrefs({bool load = true}) {
    if (load) _load();
  }

  static const String _giroKey = 'motor_anim_giro_v1';
  static const String _tremorKey = 'motor_anim_tremor_v1';
  static const String _calorKey = 'motor_anim_calor_v1';
  static const String _alarmeKey = 'motor_anim_alarme_v1';

  MotorAnimationEffects _efeitos = const MotorAnimationEffects();
  MotorAnimationEffects get efeitos => _efeitos;

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _efeitos = MotorAnimationEffects(
        giro: prefs.getBool(_giroKey) ?? true,
        tremor: prefs.getBool(_tremorKey) ?? true,
        calor: prefs.getBool(_calorKey) ?? true,
        alarme: prefs.getBool(_alarmeKey) ?? true,
      );
      notifyListeners();
    } catch (_) {
      // Sem armazenamento, valem os padrões (tudo ligado).
    }
  }

  Future<void> set(MotorAnimationEffects efeitos) async {
    if (efeitos == _efeitos) return;
    _efeitos = efeitos;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_giroKey, efeitos.giro);
      await prefs.setBool(_tremorKey, efeitos.tremor);
      await prefs.setBool(_calorKey, efeitos.calor);
      await prefs.setBool(_alarmeKey, efeitos.alarme);
    } catch (_) {}
  }
}
