(() => {
  'use strict';

  const btn = document.getElementById('motorSoundTestBtn');
  if (!btn) return;

  let ctx = null;
  let stopTimer = null;
  let activeNodes = [];

  function makeNoiseBuffer(audioCtx, seconds = 2) {
    const length = Math.max(1, Math.floor(audioCtx.sampleRate * seconds));
    const buffer = audioCtx.createBuffer(1, length, audioCtx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i += 1) data[i] = Math.random() * 2 - 1;
    return buffer;
  }

  async function stopMotorSound() {
    if (!ctx || activeNodes.length === 0) {
      btn.textContent = '🔊 Testar som do motor';
      btn.setAttribute('aria-pressed', 'false');
      return;
    }

    if (stopTimer) {
      clearTimeout(stopTimer);
      stopTimer = null;
    }

    const now = ctx.currentTime;
    for (const item of activeNodes) {
      try {
        item.master.gain.cancelScheduledValues(now);
        item.master.gain.setValueAtTime(Math.max(item.master.gain.value, 0.0001), now);
        item.master.gain.exponentialRampToValueAtTime(0.0001, now + 0.75);
      } catch (_) {}
    }

    const nodes = activeNodes.slice();
    activeNodes = [];
    btn.textContent = '🔊 Testar som do motor';
    btn.setAttribute('aria-pressed', 'false');

    setTimeout(() => {
      for (const item of nodes) {
        for (const node of item.sources) {
          try { node.stop(); } catch (_) {}
        }
      }
    }, 850);
  }

  async function startMotorSound() {
    if (activeNodes.length) {
      await stopMotorSound();
      return;
    }

    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) {
      btn.textContent = 'Áudio não suportado';
      btn.disabled = true;
      return;
    }

    ctx = ctx || new AudioCtx();
    if (ctx.state === 'suspended') await ctx.resume();

    const now = ctx.currentTime;
    const master = ctx.createGain();
    master.gain.setValueAtTime(0.0001, now);
    master.gain.exponentialRampToValueAtTime(0.28, now + 0.65);
    master.gain.setValueAtTime(0.28, now + 4.0);
    master.gain.exponentialRampToValueAtTime(0.0001, now + 4.8);
    master.connect(ctx.destination);

    const hum60 = ctx.createOscillator();
    hum60.type = 'sine';
    hum60.frequency.setValueAtTime(42, now);
    hum60.frequency.exponentialRampToValueAtTime(60, now + 0.65);
    const g60 = ctx.createGain();
    g60.gain.value = 0.62;
    hum60.connect(g60).connect(master);

    const hum120 = ctx.createOscillator();
    hum120.type = 'sine';
    hum120.frequency.setValueAtTime(84, now);
    hum120.frequency.exponentialRampToValueAtTime(120, now + 0.65);
    const g120 = ctx.createGain();
    g120.gain.value = 0.24;
    hum120.connect(g120).connect(master);

    const hum180 = ctx.createOscillator();
    hum180.type = 'triangle';
    hum180.frequency.setValueAtTime(126, now);
    hum180.frequency.exponentialRampToValueAtTime(180, now + 0.65);
    const g180 = ctx.createGain();
    g180.gain.value = 0.10;
    hum180.connect(g180).connect(master);

    const wobble = ctx.createOscillator();
    wobble.type = 'sine';
    wobble.frequency.value = 2.2;
    const wobbleGain = ctx.createGain();
    wobbleGain.gain.value = 0.018;
    wobble.connect(wobbleGain).connect(master.gain);

    const noise = ctx.createBufferSource();
    noise.buffer = makeNoiseBuffer(ctx, 1.8);
    noise.loop = true;
    const noiseFilter = ctx.createBiquadFilter();
    noiseFilter.type = 'bandpass';
    noiseFilter.frequency.value = 260;
    noiseFilter.Q.value = 0.8;
    const noiseGain = ctx.createGain();
    noiseGain.gain.value = 0.045;
    noise.connect(noiseFilter).connect(noiseGain).connect(master);

    const sources = [hum60, hum120, hum180, wobble, noise];
    for (const source of sources) source.start(now);

    activeNodes = [{ master, sources }];
    btn.textContent = '■ Parar teste de som';
    btn.setAttribute('aria-pressed', 'true');

    stopTimer = setTimeout(() => {
      stopMotorSound();
    }, 4800);
  }

  btn.setAttribute('aria-pressed', 'false');
  btn.addEventListener('click', startMotorSound);
})();