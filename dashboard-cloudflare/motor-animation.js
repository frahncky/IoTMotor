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

  // Mesmo tempo do som: partida em 1,8 s e desaceleração ao desligar.
  const STARTUP_S = 1.8;
  const COAST_TAU_S = 1.2;
  const STOPPED = 0.004;

  const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)');
  const smoothstep = (x) => x * x * (3 - 2 * x);

  // progress avança linearmente na partida; speed = smoothstep(progress) dá
  // o arranque suave. Na parada a velocidade decai de forma exponencial.
  let progress = 0;
  let speed = 0;
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
      progress = Math.min(1, progress + dt / STARTUP_S);
      speed = smoothstep(progress);
    } else if (speed > 0) {
      speed *= Math.exp(-dt / COAST_TAU_S);
      if (speed < STOPPED) speed = 0;
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
