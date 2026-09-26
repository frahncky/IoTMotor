(() => {
  'use strict';

  const visual = document.getElementById('motorVisual');
  const fan = visual?.querySelector('.motor-fan');
  if (!visual || !fan) return;

  let angle = 0;
  let last = performance.now();
  let raf = 0;

  // Rotação visual deliberadamente mais lenta que a rotação física do motor,
  // para as pás permanecerem perceptíveis na interface.
  const DEGREES_PER_SECOND = 720;

  function frame(now) {
    const dt = Math.min(64, Math.max(0, now - last));
    last = now;

    if (visual.dataset.state === 'running') {
      angle = (angle + (DEGREES_PER_SECOND * dt / 1000)) % 360;
      // O grupo da ventoinha agora é centrado em (0,0). Isso impede que
      // qualquer parte do SVG descreva órbitas pelo restante do desenho.
      fan.setAttribute('transform', `rotate(${angle.toFixed(2)})`);
    }

    raf = requestAnimationFrame(frame);
  }

  function syncState() {
    last = performance.now();
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