/**
 * Tokens visuais do painel — estilo "blueprint".
 *
 * As cores de superficie, texto e destaque foram amostradas da peca de
 * referencia (fundo #0F172A ocupando 64% da arte, azul de titulo #5EA8FC,
 * azul de preenchimento das formas solidas #4C85CC).
 *
 * As cores de serie NAO vieram da referencia: ela e monocromatica em azul, o
 * que nao distingue duas series num mesmo grafico. Sao os passos de modo
 * escuro da rampa categorica validada, e os unicos pares que coexistem num
 * grafico — (potencia ativa, aparente) e (vibracao RMS, pico) — passaram nas
 * verificacoes de separacao para daltonismo e de contraste sobre o card.
 */
export const C = {
  // Superficies
  bg:            "#0F172A",  // fundo da pagina
  surface:       "#1B2336",  // cards (e a superficie dos graficos)
  surfaceRaised: "#243049",  // campos de entrada
  border:        "#24304A",
  borderStrong:  "#33415C",

  // Texto
  text:   "#FFFFFF",
  muted:  "#94A3B8",
  faint:  "#64748B",  // so decoracao: 3.75:1, abaixo de AA para corpo de texto

  // Destaque da marca
  accent:     "#5EA8FC",  // titulos, icones, traços — 7.21:1 sobre o fundo
  accentFill: "#4C85CC",  // formas solidas e botao primario

  // Estado
  good: "#34D399",
  warn: "#FBBF24",
  bad:  "#F87171",

  // Rampa categorica (passos de modo escuro)
  blue:    "#3987e5",
  orange:  "#d95926",
  yellow:  "#c98500",
  aqua:    "#199e70",
  magenta: "#d55181",
};

export default C;
