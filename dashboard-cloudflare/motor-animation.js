(() => {
  'use strict';

  const visual = document.getElementById('motorVisual');
  const fan = visual?.querySelector('.motor-fan');
  if (!visual || !fan) return;
  const rotor = visual.querySelector('.motor-rotor');
  const shaft = visual.querySelector('.motor-shaft-rotor');

  // Graus por segundo na rotação nominal. A ventoinha faz ~2,6 voltas/s:
  // rápido o bastante para parecer um motor, mas o marcador âmbar ainda
  // deixa o giro visível. Rotor e eixo mantêm a proporção anterior.
  const PARTS = [
    { el: fan, dps: 936, attr: true },
    { el: rotor, dps: 857 },
    { el: shaft, dps: 643 },
  ].filter((part) => part.el);
  for (const part of PARTS) part.angle = 0;

  // Mesmas curvas do som (motor-sound.js): partida em 1,8 s e, ao desligar,
  // desaceleração que chega a zero em até 3,4 s, proporcional à velocidade.
  const STARTUP_S = 1.8;
  const COAST_S = 3.4;
  const easeCoast = (x) => (1 - Math.exp(-2.2 * x)) / (1 - Math.exp(-2.2));

  const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)');
  const smoothstep = (x) => x * x * (3 - 2 * x);

  // progress avança linearmente na partida; speed = smoothstep(progress) dá
  // o arranque suave. Na parada segue easeCoast a partir da velocidade atual.
  let progress = 0;
  let speed = 0;
  let coast = null;
  let last = performance.now();
  let raf = 0;

  // Religando no meio da desaceleração: retoma do ponto equivalente da curva.
  function progressFor(value) {
    let lo = 0, hi = 1;
    for (let i = 0; i < 20; i += 1) {
      const mid = (lo + hi) / 2;
      if (smoothstep(mid) < value) lo = mid; else hi = mid;
    }
    return (lo + hi) / 2;
  }

  let wasRunning = false;

  function frame(now) {
    const dt = Math.min(0.064, Math.max(0, (now - last) / 1000));
    last = now;
    const running = visual.dataset.state === 'running';

    if (running) {
      if (!wasRunning) progress = progressFor(speed);
      coast = null;
      progress = Math.min(1, progress + dt / STARTUP_S);
      speed = smoothstep(progress);
    } else if (speed > 0) {
      if (!coast) coast = { from: speed, elapsed: 0, total: COAST_S * Math.max(0.25, speed) };
      coast.elapsed += dt;
      const x = coast.elapsed / coast.total;
      speed = x >= 1 ? 0 : coast.from * (1 - easeCoast(x));
    }
    wasRunning = running;

    if (speed > 0 && !reduceMotion?.matches) {
      for (const part of PARTS) {
        part.angle = (part.angle + part.dps * speed * dt) % 360;
        if (part.attr) part.el.setAttribute('transform', `rotate(${part.angle.toFixed(2)} 118 240)`);
        else part.el.style.transform = `rotate(${part.angle.toFixed(2)}deg)`;
      }
    }

    raf = requestAnimationFrame(frame);
  }

  raf = requestAnimationFrame(frame);

  window.addEventListener('pagehide', () => {
    if (raf) cancelAnimationFrame(raf);
  }, { once: true });
})();
