'use strict';
// Histórico por hora dos últimos 7 dias, guardado na placa de sensores
// (historico.h). Cada dia chega num tópico retido <prefixo>/<sensores>/history/<0..6>,
// então o gráfico abre preenchido mesmo que o painel tenha ficado fechado.
//
// Linha de cada hora: [hora, corrente média, corrente máx, tensão média,
// temperatura média, temperatura máx, vibração média, vibração máx, minutos
// ligado], em centésimos de A, décimos de V e °C e milésimos de g.

const HORA_MS = 3600000, DIA_MS = 24 * HORA_MS, DIAS = 7;
const GRANDEZAS_HISTORICO = [
  {id: 'corrente', nome: 'Corrente', unidade: 'A', media: 1, maximo: 2, escala: 100, casas: 2, cor: '#ffc46a'},
  {id: 'temperatura', nome: 'Temperatura', unidade: '°C', media: 4, maximo: 5, escala: 10, casas: 1, cor: '#f69d84'},
  {id: 'vibracao', nome: 'Vibração RMS', unidade: 'g', media: 6, maximo: 7, escala: 1000, casas: 3, cor: '#e6b2d4'},
  {id: 'tensao', nome: 'Tensão', unidade: 'V', media: 3, maximo: null, escala: 10, casas: 1, cor: '#65c7e8'},
  {id: 'ligado', nome: 'Tempo ligado', unidade: 'min/h', media: 8, maximo: null, escala: 1, casas: 0, cor: '#83d8a2', barras: true}
];

// Lê um dia publicado pela placa; null se não for um dia válido.
function lerDia(dados) {
  if (!dados || !Number.isInteger(dados.day) || dados.day <= 0 || !Array.isArray(dados.hours)) return null;
  const horas = dados.hours.filter(l => Array.isArray(l) && l.length >= 9 && Number.isInteger(l[0]) && l[0] >= 0 && l[0] < 24);
  return {dia: dados.day, horas};
}

// Pontos de uma grandeza nos últimos 7 dias, em ordem: {t (ms), media, maximo}.
function serieDoHistorico(dias, grandeza, agoraMs) {
  const inicio = agoraMs - DIAS * DIA_MS;
  const pontos = [];
  for (const d of dias) {
    if (!d) continue;
    for (const l of d.horas) {
      const t = (d.dia * 24 + l[0]) * HORA_MS;
      if (t < inicio - HORA_MS || t > agoraMs) continue;
      const valor = i => (i === null || !Number.isFinite(l[i]) ? null : l[i] / grandeza.escala);
      const media = valor(grandeza.media);
      if (media === null) continue;
      pontos.push({t, media, maximo: valor(grandeza.maximo)});
    }
  }
  return pontos.sort((a, b) => a.t - b.t);
}

function numeroBr(v, casas) { return v.toFixed(casas).replace('.', ','); }

// Resumo dos 7 dias: tempo ligado e os picos de corrente e temperatura.
function resumoDoHistorico(dias, agoraMs) {
  const ligado = serieDoHistorico(dias, GRANDEZAS_HISTORICO[4], agoraMs).reduce((s, p) => s + p.media, 0);
  if (!dias.some(d => d?.horas.length)) return '';
  const partes = [`Motor ligado ${Math.floor(ligado / 60)} h ${String(Math.round(ligado % 60)).padStart(2, '0')} min em 7 dias`];
  for (const g of GRANDEZAS_HISTORICO.slice(0, 2)) {
    const picos = serieDoHistorico(dias, g, agoraMs).map(p => p.maximo ?? p.media);
    if (picos.length) partes.push(`${g.nome} máxima ${numeroBr(Math.max(...picos), g.casas)} ${g.unidade}`);
  }
  return partes.join(' · ');
}

if (typeof document !== 'undefined') (() => {
  const $ = id => document.getElementById(id);
  if (!$('historyChart')) return;
  const NS = 'http://www.w3.org/2000/svg';
  const svg = (tag, attrs = {}, texto) => {
    const n = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
    if (texto !== undefined) n.textContent = texto;
    return n;
  };
  let client = null, prefixo = '', dispositivo = 'esp32-02', escolhida = 'corrente';
  const dias = new Array(DIAS).fill(null);
  try { const salva = localStorage.getItem('iotmotor_historico'); if (GRANDEZAS_HISTORICO.some(g => g.id === salva)) escolhida = salva; } catch {}

  function botoes() {
    const alvo = $('historyFilters');
    alvo.replaceChildren();
    for (const g of GRANDEZAS_HISTORICO) {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = g.nome;
      b.setAttribute('aria-pressed', String(g.id === escolhida));
      b.addEventListener('click', () => {
        escolhida = g.id;
        try { localStorage.setItem('iotmotor_historico', g.id); } catch {}
        botoes(); desenhar();
      });
      alvo.append(b);
    }
  }

  function desenhar() {
    const g = GRANDEZAS_HISTORICO.find(x => x.id === escolhida);
    const agora = Date.now();
    const pontos = serieDoHistorico(dias, g, agora);
    const grafico = $('historyChart');
    grafico.replaceChildren();
    grafico.setAttribute('aria-label', `Histórico de ${g.nome} nos últimos 7 dias`);
    $('historyResumo').textContent = client ? (resumoDoHistorico(dias, agora) ||
      'A placa de sensores ainda não publicou histórico (precisa do firmware novo e da hora da internet).')
      : 'Conecte ao MQTT para ver o histórico guardado na placa.';
    // Uma unidade do desenho por pixel: o gráfico ocupa a largura toda sem esticar o texto.
    const W = Math.max(320, Math.round(grafico.getBoundingClientRect?.().width || 650)), H = 215, E = 46, D = 10, T = 10, B = 26;
    grafico.setAttribute('viewBox', `0 0 ${W} ${H}`);
    const x0 = agora - DIAS * DIA_MS;
    const x = t => E + (t - x0) / (agora - x0) * (W - E - D);
    const valores = pontos.flatMap(p => [p.media, p.maximo]).filter(Number.isFinite);
    const baseZero = g.barras || g.id === 'corrente' || g.id === 'vibracao';
    let min = valores.length ? Math.min(...valores) : 0, max = valores.length ? Math.max(...valores) : 1;
    if (baseZero) min = 0;
    if (g.barras) max = 60;
    if (max - min < 1e-9) { max += 1; if (!baseZero) min -= 1; }
    const folga = (max - min) * 0.08;
    if (!g.barras) { max += folga; if (!baseZero) min -= folga; }
    const y = v => T + (1 - (v - min) / (max - min)) * (H - T - B);
    // Grade: meia-noite de cada dia (hora local) e os extremos do eixo.
    const meiaNoite = new Date(x0); meiaNoite.setHours(24, 0, 0, 0);
    for (let t = meiaNoite.getTime(); t < agora; t += DIA_MS) {
      grafico.append(svg('line', {x1: x(t), x2: x(t), y1: T, y2: H - B, class: 'gridline'}));
      grafico.append(svg('text', {x: x(t) + 3, y: H - 8},
        new Date(t).toLocaleDateString('pt-BR', {day: '2-digit', month: '2-digit'})));
    }
    for (const v of [min, max]) grafico.append(svg('text', {x: 4, y: y(v) + 4}, numeroBr(v, g.barras ? 0 : g.casas)));
    grafico.append(svg('text', {x: 4, y: H - 8}, g.unidade));
    if (!pontos.length) {
      grafico.append(svg('text', {x: W / 2, y: H / 2, class: 'empty', 'text-anchor': 'middle'}, 'Sem registros nestes 7 dias'));
      $('historyLegenda').textContent = '';
      return;
    }
    if (g.barras) {
      const largura = Math.max(1, x(HORA_MS) - x(0) - 0.5);
      for (const p of pontos) if (p.media > 0)
        grafico.append(svg('rect', {x: x(p.t), y: y(p.media), width: largura, height: y(0) - y(p.media), fill: g.cor}));
      $('historyLegenda').textContent = 'Barras: minutos ligado em cada hora.';
      return;
    }
    // Linhas quebradas onde falta hora (placa desligada ou sem leitura).
    const trilha = chave => {
      let d = '', anterior = null;
      for (const p of pontos) {
        if (!Number.isFinite(p[chave])) { anterior = null; continue; }
        d += `${anterior !== null && p.t - anterior <= HORA_MS ? 'L' : 'M'}${x(p.t + HORA_MS / 2).toFixed(1)} ${y(p[chave]).toFixed(1)} `;
        anterior = p.t;
      }
      return d.trim();
    };
    if (g.maximo !== null) grafico.append(svg('path', {d: trilha('maximo'), fill: 'none', stroke: g.cor, 'stroke-width': 1.5, 'stroke-dasharray': '4 3', opacity: 0.7}));
    grafico.append(svg('path', {d: trilha('media'), fill: 'none', stroke: g.cor, 'stroke-width': 2.2}));
    // Pontos isolados (hora sem vizinhas) viram bolinhas para não sumir.
    pontos.forEach((p, i) => {
      const vizinha = q => q && Math.abs(q.t - p.t) <= HORA_MS;
      if (!vizinha(pontos[i - 1]) && !vizinha(pontos[i + 1]))
        grafico.append(svg('circle', {cx: x(p.t + HORA_MS / 2), cy: y(p.media), r: 2.5, fill: g.cor}));
    });
    $('historyLegenda').textContent = g.maximo !== null
      ? `Linha cheia: média de cada hora · tracejada: máximo da hora${g.id === 'temperatura' || g.id === 'tensao' ? '' : ' (só com o motor ligado)'}.`
      : 'Média de cada hora.';
  }

  function desconectar() {
    const antigo = client;
    client = null;
    dias.fill(null);
    if (antigo) antigo.end(true);
    desenhar();
  }

  function conectar() {
    desconectar();
    if (!window.mqtt?.connect) return;
    let url;
    try {
      url = new URL(String($('broker').value || '').trim());
      prefixo = String($('prefix').value || '').trim().replace(/^\/+|\/+$/g, '');
      dispositivo = String($('sensorDevice').value || '').trim();
      if (url.protocol !== 'wss:' || !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(prefixo) || !/^[a-zA-Z0-9_-]+$/.test(dispositivo)) return;
    } catch { return; }
    const ativo = window.mqtt.connect(url.toString(), {
      clientId: `iotmotor_hist_${Math.random().toString(36).slice(2, 12)}`,
      clean: true, reconnectPeriod: 4000, connectTimeout: 10000, protocolVersion: 4, keepalive: 30
    });
    client = ativo;
    const base = `${prefixo}/${dispositivo}/history/`;
    ativo.on('connect', () => { if (client === ativo) ativo.subscribe(base + '+', {qos: 1}); });
    ativo.on('message', (nome, payload) => {
      if (client !== ativo || !nome.startsWith(base)) return;
      const slot = Number(nome.slice(base.length));
      if (!Number.isInteger(slot) || slot < 0 || slot >= DIAS) return;
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (dados?.device_id !== dispositivo) return;
      dias[slot] = lerDia(dados);
      desenhar();
    });
    desenhar();
  }

  let redesenho = null;
  window.addEventListener?.('resize', () => { clearTimeout(redesenho); redesenho = setTimeout(desenhar, 150); });
  botoes();
  window.iotmotorHistorico = {connect: conectar, disconnect: desconectar};
  desenhar();
})();

if (typeof module !== 'undefined' && module.exports)
  module.exports = {lerDia, serieDoHistorico, resumoDoHistorico, GRANDEZAS_HISTORICO};
