(() => {
  'use strict';

  const visual = document.getElementById('motorVisual');
  const fan = visual?.querySelector('.motor-fan');
  if (!visual || !fan) return;

  let angle = 0;
  let last = performance.now();
  let raf = 0;

  // Aproximadamente 2,6 voltas/s: rápido o bastante para parecer um motor,
  // mas lento o suficiente para o marcador âmbar deixar o giro visível.
  const DEGREES_PER_SECOND = 936;

  function frame(now) {
    const dt = Math.min(64, Math.max(0, now - last));
    last = now;

    if (visual.dataset.state === 'running') {
      angle = (angle + (DEGREES_PER_SECOND * dt / 1000)) % 360;
      fan.setAttribute('transform', `rotate(${angle.toFixed(2)} 118 240)`);
    }

    raf = requestAnimationFrame(frame);
  }

  function syncState() {
    if (visual.dataset.state !== 'running') {
      // Mantém a posição onde parou; ao religar o giro continua sem "salto".
      last = performance.now();
    }
  }

  new MutationObserver(syncState).observe(visual, {
    attributes: true,
    attributeFilter: ['data-state'],
  });

  raf = requestAnimationFrame(frame);

  window.addEventListener('pagehide', () => {
    if (raf) cancelAnimationFrame(raf);
  }, { once: true });
})();