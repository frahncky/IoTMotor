import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppVisualVariant { modern, industrial, blueprint }

class AppTheme {
  // Troque esta linha para voltar a variante anterior: nada mais depende dela.
  static const AppVisualVariant activeVariant = AppVisualVariant.blueprint;

  static const _AppPalette _modernPalette = _AppPalette(
    brandBlue: Color(0xFF1F8BA5),
    brandMint: Color(0xFF34C5AA),
    brandOrange: Color(0xFFFFA149),
    surfaceSoft: Color(0xFFF6FAFD),
    background: Color(0xFFEAF1F7),
    ink: Color(0xFF142734),
    inkSoft: Color(0xFF405667),
    bodySoft: Color(0xFF557085),
    labelSoft: Color(0xFF5A7488),
    inputBorder: Color(0xFF9EB9CE),
    navMuted: Color(0xFF6E8597),
    switchOffTrack: Color(0xFFB8CAD8),
    online: Color(0xFF0E9F6E),
    offline: Color(0xFFC2410C),
    danger: Color(0xFFD94841),
    voltageAccent: Color(0xFF0A84FF),
    currentAccent: Color(0xFFEF7E30),
    vibrationAccent: Color(0xFF1F9F82),
    temperatureAccent: Color(0xFFC06034),
    backgroundGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFFF8FBFE), Color(0xFFE9F1F8), Color(0xFFF2F7FB)],
      stops: <double>[0, 0.52, 1],
    ),
  );

  static const _AppPalette _industrialPalette = _AppPalette(
    brandBlue: Color(0xFF8EA4C4),
    brandMint: Color(0xFFF0B90B),
    brandOrange: Color(0xFFF3BA2F),
    surfaceSoft: Color(0xFF222B38),
    background: Color(0xFF141C28),
    ink: Color(0xFFF4F7FB),
    inkSoft: Color(0xFFBCC5D3),
    bodySoft: Color(0xFFB8C1CF),
    labelSoft: Color(0xFFA4AFBF),
    inputBorder: Color(0xFF5A6780),
    navMuted: Color(0xFFB3BECE),
    switchOffTrack: Color(0xFF4D5769),
    online: Color(0xFF0ECB81),
    offline: Color(0xFFF6465D),
    danger: Color(0xFFF6465D),
    voltageAccent: Color(0xFFF0B90B),
    currentAccent: Color(0xFF7EB4FF),
    vibrationAccent: Color(0xFF35C9B6),
    temperatureAccent: Color(0xFFFF8A65),
    backgroundGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF161E2B), Color(0xFF1D2737), Color(0xFF121A26)],
      stops: <double>[0, 0.55, 1],
    ),
  );

  /// Paleta "blueprint": fundo naval, azul de destaque e texto branco.
  ///
  /// As cores de superficie, texto e destaque foram amostradas de uma peca de
  /// referencia (fundo #0F172A, azul de titulo #5EA8FC, azul das formas
  /// solidas #4C85CC). Os acentos de grandeza vem da mesma rampa categorica
  /// usada no dashboard web, para que app e painel falem a mesma lingua visual.
  ///
  /// Observacao sobre os nomes: `brandMint` e o slot de acento primario desta
  /// classe, nao um tom de menta — nas outras variantes ele ja guarda um verde
  /// (modern) e um amarelo (industrial). Aqui guarda o azul de preenchimento.
  static const _AppPalette _blueprintPalette = _AppPalette(
    brandBlue: Color(0xFF5EA8FC),
    brandMint: Color(0xFF4C85CC),
    brandOrange: Color(0xFFFBBF24),
    surfaceSoft: Color(0xFF1B2336),
    background: Color(0xFF0F172A),
    ink: Color(0xFFFFFFFF),
    inkSoft: Color(0xFFCBD5E1),
    bodySoft: Color(0xFF94A3B8),
    labelSoft: Color(0xFF94A3B8),
    inputBorder: Color(0xFF33415C),
    navMuted: Color(0xFF94A3B8),
    switchOffTrack: Color(0xFF33415C),
    online: Color(0xFF34D399),
    offline: Color(0xFFF87171),
    danger: Color(0xFFF87171),
    voltageAccent: Color(0xFF3987E5),
    currentAccent: Color(0xFFD95926),
    vibrationAccent: Color(0xFF3987E5),
    temperatureAccent: Color(0xFFD95926),
    backgroundGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF0F172A), Color(0xFF142039), Color(0xFF0F172A)],
      stops: <double>[0, 0.55, 1],
    ),
  );

  static ThemeData light() {
    final _AppPalette palette = _paletteFor(activeVariant);
    final bool isDark = activeVariant != AppVisualVariant.modern;
    final Color iconBaseColor =
        isDark ? palette.ink.withValues(alpha: 0.96) : palette.inkSoft;
    final Color iconMutedColor =
        isDark ? palette.ink.withValues(alpha: 0.84) : palette.bodySoft;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: palette.brandMint,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: palette.brandMint,
      secondary: palette.brandBlue,
      surface: palette.surfaceSoft,
      tertiary: palette.brandMint,
      onSurface: palette.ink,
    );

    final TextTheme base =
        (isDark
                ? ThemeData.dark(useMaterial3: true)
                : ThemeData.light(useMaterial3: true))
            .textTheme;
    final TextTheme typography = GoogleFonts.manropeTextTheme(base).copyWith(
      displaySmall: GoogleFonts.outfit(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        color: palette.ink,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: palette.ink,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: palette.ink,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: palette.ink,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: palette.inkSoft,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: palette.bodySoft,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: palette.ink,
      ),
      labelMedium: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: palette.labelSoft,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      splashFactory: InkRipple.splashFactory,
      textTheme: typography,
      iconTheme: IconThemeData(color: iconBaseColor, size: 22),
      primaryIconTheme: IconThemeData(color: iconBaseColor, size: 22),
      disabledColor: iconMutedColor.withValues(alpha: 0.55),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: typography.titleLarge,
        iconTheme: IconThemeData(color: iconBaseColor, size: 22),
        actionsIconTheme: IconThemeData(color: iconBaseColor, size: 22),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceSoft.withValues(alpha: isDark ? 0.96 : 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: palette.inputBorder.withValues(alpha: 0.55),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.brandMint, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        backgroundColor: palette.surfaceSoft.withValues(alpha: 0.92),
        selectedColor: palette.brandMint.withValues(alpha: 0.18),
        labelStyle: typography.labelMedium?.copyWith(color: palette.inkSoft),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: palette.brandMint,
          foregroundColor: isDark ? palette.background : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: typography.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: typography.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.brandMint,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: palette.brandMint.withValues(alpha: 0.3)),
          textStyle: typography.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return palette.brandMint;
            }
            return iconBaseColor;
          }),
          iconColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return palette.brandMint;
            }
            return iconBaseColor;
          }),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceSoft,
        iconColor: iconBaseColor,
        textStyle: typography.bodyMedium?.copyWith(color: palette.ink),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: iconBaseColor,
        textColor: palette.ink,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: palette.brandMint.withValues(alpha: 0.32),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return typography.labelMedium?.copyWith(
            color:
                selected
                    ? palette.brandMint
                    : palette.ink.withValues(alpha: 0.9),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color:
                selected
                    ? palette.brandMint
                    : palette.ink.withValues(alpha: 0.92),
            size: selected ? 24 : 23,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return palette.brandMint;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return palette.brandMint.withValues(alpha: 0.4);
          }
          return palette.switchOffTrack;
        }),
      ),
    );
  }

  static _AppPalette _paletteFor(AppVisualVariant variant) {
    switch (variant) {
      case AppVisualVariant.modern:
        return _modernPalette;
      case AppVisualVariant.industrial:
        return _industrialPalette;
      case AppVisualVariant.blueprint:
        return _blueprintPalette;
    }
  }

  static _AppPalette get _palette => _paletteFor(activeVariant);

  static Color get brandBlue => _palette.brandBlue;
  static Color get brandMint => _palette.brandMint;
  static Color get brandOrange => _palette.brandOrange;
  static Color get surfaceSoft => _palette.surfaceSoft;
  static Color get background => _palette.background;
  static Color get ink => _palette.ink;
  static Color get inkSoft => _palette.inkSoft;
  static Color get bodySoft => _palette.bodySoft;
  static Color get labelSoft => _palette.labelSoft;
  static Color get inputBorder => _palette.inputBorder;
  static Color get navMuted => _palette.navMuted;
  static Color get switchOffTrack => _palette.switchOffTrack;
  static Color get online => _palette.online;
  static Color get offline => _palette.offline;
  static Color get danger => _palette.danger;
  static Color get voltageAccent => _palette.voltageAccent;
  static Color get currentAccent => _palette.currentAccent;
  static Color get vibrationAccent => _palette.vibrationAccent;
  static Color get temperatureAccent => _palette.temperatureAccent;
  static Gradient get appBackgroundGradient => _palette.backgroundGradient;
}

class _AppPalette {
  const _AppPalette({
    required this.brandBlue,
    required this.brandMint,
    required this.brandOrange,
    required this.surfaceSoft,
    required this.background,
    required this.ink,
    required this.inkSoft,
    required this.bodySoft,
    required this.labelSoft,
    required this.inputBorder,
    required this.navMuted,
    required this.switchOffTrack,
    required this.online,
    required this.offline,
    required this.danger,
    required this.voltageAccent,
    required this.currentAccent,
    required this.vibrationAccent,
    required this.temperatureAccent,
    required this.backgroundGradient,
  });

  final Color brandBlue;
  final Color brandMint;
  final Color brandOrange;
  final Color surfaceSoft;
  final Color background;
  final Color ink;
  final Color inkSoft;
  final Color bodySoft;
  final Color labelSoft;
  final Color inputBorder;
  final Color navMuted;
  final Color switchOffTrack;
  final Color online;
  final Color offline;
  final Color danger;
  final Color voltageAccent;
  final Color currentAccent;
  final Color vibrationAccent;
  final Color temperatureAccent;
  final Gradient backgroundGradient;
}
