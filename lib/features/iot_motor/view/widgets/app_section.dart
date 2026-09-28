import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Bloco de conteúdo das telas (menos o Início): superfície lisa, sem borda,
/// sem sombra e sem animação, com título curto e o conteúdo logo abaixo.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  final String? title;
  final String? subtitle;

  /// Ação ou interruptor à direita do título.
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    // Material (e não um Container pintado) para o toque das listas mostrar
    // o efeito de clique por cima do fundo.
    return Material(
      color: AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title!, style: texto.titleMedium),
                          if (subtitle != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(subtitle!, style: texto.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Botões empilhados, todos com a mesma largura: o principal em cima.
class AppButtons extends StatelessWidget {
  const AppButtons({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}

/// Linha "rótulo · valor" de uma lista de leitura.
class AppInfoRow extends StatelessWidget {
  const AppInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: texto.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: texto.bodyMedium?.copyWith(
                color: AppTheme.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Espaço padrão entre blocos de uma tela.
const SizedBox appSectionGap = SizedBox(height: 12);

/// Margem padrão das telas roladas (fica acima da barra inferior).
const EdgeInsets appPagePadding = EdgeInsets.fromLTRB(16, 12, 16, 24);
