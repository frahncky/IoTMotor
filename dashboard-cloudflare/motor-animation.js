'use strict';

function motorClamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function motorSmoothstep(x) {
  const v = motorClamp(Number(x) || 0, 0, 1);
  return v * v * (3 - 2 * v);
}

// A animação representa a rotação, mas não tenta desenhar literalmente dezenas
// de voltas por segundo. O RPM de placa só escala a velocidade visual.
function visualDpsForRpm(rpm) {
  const nominal = Number.isFinite(Number(rpm)) && Number(rpm) > 0 ? Number(rpm) : 1750;
  const x = motorClamp((nominal - 600) / 3000, 0, 1);
  return 540 + 720 * Math.pow(x, 0.72);
}

function startupDurationForKind(kind) {
  if (kind === 'star-delta') return 2.8;
  if (kind === 'sequenced') return 2.2;
  return 1.5;
}

// Partida direta: aceleração contínua.
// Sequenciada/estrela-triângulo: pequena queda visual na comutação, sem
// inventar uma parada do motor.
function startupSpeed(progress, kind) {
  const x = motorClamp(Number(progress) || 0, 0, 1);
  const base = motorSmoothstep(x);
  if (kind !== 'star-delta' && kind !== 'sequenced') return base;
  const centro = kind === 'star-delta' ? 0.61 : 0.64;
  const largura = kind === 'star-delta' ? 0.055 : 0.075;
  const profundidade = kind === 'star-delta' ? 0.16 : 0.08;
  const z = (x - centro) / largura;
  const dip = profundidade * Math.exp(-(z * z));
  return motorClamp(base * (1 - dip), 0, 1);
}
// Parada por inércia: um pouco mais longa quando o motor estava perto do
// regime, sem "cortar" a rotação de forma digital.
const MOTOR_COAST_S = 3.6;

function coastDuration(from) {
  return MOTOR_COAST_S * Math.max(0.28, Math.pow(motorClamp(Number(from) || 0, 0, 1), 0.72));
}

function coastSpeed(from, elapsed, total) {
  const x = total > 0 ? elapsed / total : 1;
  if (x >= 1) return 0;
  const ease = (1 - Math.exp(-2.35 * x)) / (1 - Math.exp(-2.35));
  return from * (1 - ease);
}

function motionAppearance(speed) {
  const s = motorClamp(Number(speed) || 0, 0, 1);
  const fast = motorClamp((s - 0.48) / 0.52, 0, 1);
  return {
    blurPx: 1.15 * fast,
    bladeOpacity: 1 - 0.38 * fast,
    markerOpacity: 1 - 0.72 * fast,
  };
}

// Efeitos do desenho escolhidos em Configurações › Animação e som do motor.
// Preferência deste navegador (como o som); tudo ligado por padrão.
const ANIMACAO_CHAVE = 'iotmotor_animacao_v1';
const ANIMACAO_PADRAO = Object.freeze({giro: true, tremor: true, calor: true, alarme: true});

function lerPreferenciasAnimacao(texto) {
  let salvo = {};
  try { salvo = JSON.parse(texto || '{}') || {}; } catch (_) { salvo = {}; }
  const prefs = {...ANIMACAO_PADRAO};
  for (const chave of Object.keys(ANIMACAO_PADRAO))
    if (typeof salvo[chave] === 'boolean') prefs[chave] = salvo[chave];
  return prefs;
}

// data-anim-* do cartão: só marca o que está desligado (o CSS desliga o efeito).
function atributosAnimacao(prefs) {
  const nomes = {giro: 'animGiro', tremor: 'animTremor', calor: 'animCalor', alarme: 'animAlarme'};
  return Object.fromEntries(Object.entries(nomes).map(([chave, attr]) => [attr, prefs[chave] ? null : 'off']));
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    visualDpsForRpm,
    startupDurationForKind,
    startupSpeed,
    coastDuration,
    coastSpeed,
    motionAppearance,
    ANIMACAO_PADRAO,
    lerPreferenciasAnimacao,
    atributosAnimacao,
  };
}

if (typeof document !== 'undefined') (() => {
  const visual = document.getElementById('motorVisual');
  const fan = visual?.querySelector('.motor-fan');
  if (!visual || !fan) return;

  const rotor = visual.querySelector('.motor-rotor');
  const shaft = visual.querySelector('.motor-shaft-rotor');
  const stage = visual.querySelector('.motor-stage');
  const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)');
  // Sem giro: pelo sistema (reduzir movimento) ou pela escolha nas Configurações.
  const semGiro = () => reduceMotion?.matches || visual.dataset.animGiro === 'off';

  let prefs = {...ANIMACAO_PADRAO};
  try { prefs = lerPreferenciasAnimacao(localStorage.getItem(ANIMACAO_CHAVE)); } catch (_) {}
  function aplicarPreferencias() {
    for (const [attr, valor] of Object.entries(atributosAnimacao(prefs))) {
      if (valor) visual.dataset[attr] = valor;
      else delete visual.dataset[attr];
    }
  }
  const CAMPOS = {animGiro: 'giro', animTremor: 'tremor', animCalor: 'calor', animAlarme: 'alarme'};
  for (const [id, chave] of Object.entries(CAMPOS)) {
    const campo = document.getElementById(id);
    if (!campo) continue;
    campo.checked = prefs[chave];
    campo.addEventListener('change', () => {
      prefs = {...prefs, [chave]: campo.checked};
      try { localStorage.setItem(ANIMACAO_CHAVE, JSON.stringify(prefs)); } catch (_) {}
      aplicarPreferencias();
      wake();
    });
  }
  aplicarPreferencias();

  // Todas as peças solidárias ao eixo usam o MESMO ângulo. As diferenças
  // anteriores entre ventoinha, rotor e eixo eram visualmente úteis, mas
  // mecanicamente incorretas.
  let angle = 0;
  let progress = 0;
  let speed = 0;
  let coast = null;
  let wasRunning = false;
  let last = 0;
  let raf = 0;
  let lastAppearance = '';

  function progressFor(value, kind) {
    let lo = 0, hi = 1;
    for (let i = 0; i < 24; i += 1) {
      const mid = (lo + hi) / 2;
      if (startupSpeed(mid, kind) < value) lo = mid;
      else hi = mid;
    }
    return (lo + hi) / 2;
  }

  function setMechanicalAngle(deg) {
    fan.setAttribute('transform', `rotate(${deg.toFixed(2)} 118 240)`);
    if (rotor) rotor.style.transform = `rotate(${deg.toFixed(2)}deg)`;
    if (shaft) shaft.style.transform = `rotate(${deg.toFixed(2)}deg)`;
  }

  function applyMotionAppearance() {
    // Parado no desenho, a ventoinha fica nítida mesmo com o motor girando.
    const appearance = motionAppearance(semGiro() ? 0 : speed);
    const signature =
      `${appearance.blurPx.toFixed(2)}|${appearance.bladeOpacity.toFixed(2)}|${appearance.markerOpacity.toFixed(2)}`;
    if (signature === lastAppearance) return;
    lastAppearance = signature;
    visual.style.setProperty('--motor-blur', `${appearance.blurPx.toFixed(2)}px`);
    visual.style.setProperty('--motor-blade-opacity', appearance.bladeOpacity.toFixed(2));
    visual.style.setProperty('--motor-marker-opacity', appearance.markerOpacity.toFixed(2));
  }


  function frame(now) {
    const elapsed = Math.max(0, (now - last) / 1000);
    const dt = Math.min(0.064, elapsed);
    last = now;

    const running = visual.dataset.state === 'running';
    const kind = visual.dataset.startKind || 'direct';
    const startupSeconds = startupDurationForKind(kind);

    if (running) {
      if (!wasRunning) progress = progressFor(speed, kind);
      coast = null;
      progress = Math.min(1, progress + elapsed / startupSeconds);
      speed = startupSpeed(progress, kind);
    } else if (speed > 0) {
      if (!coast) coast = { from: speed, elapsed: 0, total: coastDuration(speed) };
      coast.elapsed += elapsed;
      speed = coastSpeed(coast.from, coast.elapsed, coast.total);
      if (speed === 0) {
        progress = 0;
        coast = null;
      }
    }

    wasRunning = running;

    if (!semGiro() && speed > 0) {
      const dps = visualDpsForRpm(Number(visual.dataset.rpm));
      angle = (angle + dps * speed * dt) % 360;
      setMechanicalAngle(angle);
    }

    applyMotionAppearance();

    // Parado: o laço dorme até o estado do motor mudar (observer abaixo),
    // em vez de acordar a CPU a cada quadro sem nada para desenhar.
    // Sem giro (reduzir movimento ou escolha do usuário) o laço também dorme.
    const moving = (running || speed > 0) && !semGiro();
    raf = moving ? requestAnimationFrame(frame) : 0;
  }

  function wake() {
    if (raf) return;
    last = performance.now();
    raf = requestAnimationFrame(frame);
  }

  new MutationObserver(wake).observe(visual, { attributes: true, attributeFilter: ['data-state'] });
  reduceMotion?.addEventListener?.('change', wake);
  wake();

  window.addEventListener('pagehide', () => {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
  });
  // Volta do cache de navegação (bfcache): retoma se o motor estiver girando.
  window.addEventListener('pageshow', wake);
})();
