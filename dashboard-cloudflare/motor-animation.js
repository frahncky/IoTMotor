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

function vibrationAmplitude(vibrationG) {
  const value = Number(vibrationG);
  if (!Number.isFinite(value) || value <= 0.005) return 0;
  return motorClamp(value * 5, 0, 2.4);
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    visualDpsForRpm,
    startupDurationForKind,
    startupSpeed,
    vibrationAmplitude,
    motionAppearance,
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

  // Todas as peças solidárias ao eixo usam o MESMO ângulo. As diferenças
  // anteriores entre ventoinha, rotor e eixo eram visualmente úteis, mas
  // mecanicamente incorretas.
  let angle = 0;
  let progress = 0;
  let speed = 0;
  let coast = null;
  let wasRunning = false;
  let last = performance.now();
  let raf = 0;
  let lastAppearance = '';

  const COAST_S = 3.6;
  const easeCoast = x => (1 - Math.exp(-2.35 * x)) / (1 - Math.exp(-2.35));

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
    const appearance = motionAppearance(speed);
    const signature =
      `${appearance.blurPx.toFixed(2)}|${appearance.bladeOpacity.toFixed(2)}|${appearance.markerOpacity.toFixed(2)}`;
    if (signature === lastAppearance) return;
    lastAppearance = signature;
    visual.style.setProperty('--motor-blur', `${appearance.blurPx.toFixed(2)}px`);
    visual.style.setProperty('--motor-blade-opacity', appearance.bladeOpacity.toFixed(2));
    visual.style.setProperty('--motor-marker-opacity', appearance.markerOpacity.toFixed(2));
  }

  function applyVibration(now, running) {
    if (!stage) return;
    if (!running || reduceMotion?.matches) {
      stage.style.transform = '';
      return;
    }
    const amp = vibrationAmplitude(Number(visual.dataset.vibration));
    if (amp <= 0) {
      stage.style.transform = '';
      return;
    }
    const t = now / 1000;
    const x = amp * (
      0.58 * Math.sin(t * Math.PI * 2 * 17) +
      0.24 * Math.sin(t * Math.PI * 2 * 29)
    );
    const y = amp * (
      0.46 * Math.sin(t * Math.PI * 2 * 23 + 0.7) +
      0.20 * Math.sin(t * Math.PI * 2 * 31)
    );
    stage.style.transform = `translate(${x.toFixed(2)}px,${y.toFixed(2)}px)`;
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
      if (!coast) {
        coast = {
          from: speed,
          elapsed: 0,
          // A inércia final fica um pouco mais longa quando o motor estava
          // próximo do regime, sem "cortar" a rotação de forma digital.
          total: COAST_S * Math.max(0.28, Math.pow(speed, 0.72)),
        };
      }
      coast.elapsed += elapsed;
      const x = coast.elapsed / coast.total;
      speed = x >= 1 ? 0 : coast.from * (1 - easeCoast(x));
      if (speed === 0) progress = 0;
    }

    wasRunning = running;

    if (!reduceMotion?.matches && speed > 0) {
      const dps = visualDpsForRpm(Number(visual.dataset.rpm));
      angle = (angle + dps * speed * dt) % 360;
      setMechanicalAngle(angle);
    }

    applyMotionAppearance();
    applyVibration(now, running && speed > 0.06);

    raf = requestAnimationFrame(frame);
  }

  raf = requestAnimationFrame(frame);

  window.addEventListener('pagehide', () => {
    if (raf) cancelAnimationFrame(raf);
  }, { once: true });
})();
