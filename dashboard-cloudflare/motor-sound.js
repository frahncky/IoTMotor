(() => {
  'use strict';

  const STORAGE_KEY = 'iotmotor_motor_sound_v1';
  const DEFAULTS = { enabled: false, volume: 70 };
  const motorVisual = document.getElementById('motorVisual');
  const enabledInput = document.getElementById('motorSoundEnabled');
  const enabledText = document.getElementById('motorSoundEnabledText');
  const volumeInput = document.getElementById('motorSoundVolume');
  const volumeValue = document.getElementById('motorSoundVolumeValue');
  const testBtn = document.getElementById('motorSoundTestBtn');
  const feedback = document.getElementById('motorSoundFeedback');

  if (!motorVisual || !enabledInput || !volumeInput || !testBtn) return;

  let settings = loadSettings();
  let ctx = null;
  let active = null;
  let testTimer = null;
  let unlocked = false;

  function clampVolume(value) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.min(100, Math.max(0, Math.round(n))) : DEFAULTS.volume;
  }

  function loadSettings() {
    try {
      const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
      return {
        enabled: raw.enabled === true,
        volume: clampVolume(raw.volume ?? DEFAULTS.volume),
      };
    } catch (_) {
      return { ...DEFAULTS };
    }
  }

  function saveSettings() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(settings)); } catch (_) {}
  }

  function setFeedback(message) {
    if (feedback) feedback.textContent = message;
  }

  function gainForVolume(volume) {
    // Curva simples: 70% fica próximo do volume aprovado no teste anterior.
    const normalized = clampVolume(volume) / 100;
    return Math.max(0.0001, 0.57 * normalized * normalized);
  }

  function makeNoiseBuffer(audioCtx, seconds = 2) {
    const length = Math.max(1, Math.floor(audioCtx.sampleRate * seconds));
    const buffer = audioCtx.createBuffer(1, length, audioCtx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i += 1) data[i] = Math.random() * 2 - 1;
    return buffer;
  }

  async function ensureAudio() {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) {
      setFeedback('Este navegador não oferece suporte ao áudio usado pelo painel.');
      testBtn.disabled = true;
      enabledInput.disabled = true;
      return false;
    }

    ctx = ctx || new AudioCtx();
    if (ctx.state === 'suspended') {
      try { await ctx.resume(); } catch (_) {}
    }
    unlocked = ctx.state === 'running';
    return unlocked;
  }

  function currentMotorState() {
    return motorVisual.dataset.state || 'offline';
  }

  function updateVolumeDisplay() {
    if (volumeValue) volumeValue.textContent = `${settings.volume}%`;
  }

  function updateEnabledText() {
    if (!enabledText) return;
    enabledText.textContent = settings.enabled ? 'Ativado' : 'Desativado';
    enabledText.dataset.state = settings.enabled ? 'on' : 'off';
  }

  function createMotorSound({ startup = true } = {}) {
    if (!ctx) return null;

    const now = ctx.currentTime;
    const master = ctx.createGain();
    const target = gainForVolume(settings.volume);

    master.gain.setValueAtTime(0.0001, now);
    if (startup) {
      master.gain.exponentialRampToValueAtTime(Math.max(target, 0.0001), now + 0.75);
    } else {
      master.gain.setValueAtTime(Math.max(target, 0.0001), now);
    }
    master.connect(ctx.destination);

    const hum60 = ctx.createOscillator();
    hum60.type = 'sine';
    hum60.frequency.setValueAtTime(startup ? 40 : 60, now);
    if (startup) hum60.frequency.exponentialRampToValueAtTime(60, now + 0.72);
    const g60 = ctx.createGain();
    g60.gain.value = 0.62;
    hum60.connect(g60).connect(master);

    const hum120 = ctx.createOscillator();
    hum120.type = 'sine';
    hum120.frequency.setValueAtTime(startup ? 80 : 120, now);
    if (startup) hum120.frequency.exponentialRampToValueAtTime(120, now + 0.72);
    const g120 = ctx.createGain();
    g120.gain.value = 0.24;
    hum120.connect(g120).connect(master);

    const hum180 = ctx.createOscillator();
    hum180.type = 'triangle';
    hum180.frequency.setValueAtTime(startup ? 120 : 180, now);
    if (startup) hum180.frequency.exponentialRampToValueAtTime(180, now + 0.72);
    const g180 = ctx.createGain();
    g180.gain.value = 0.10;
    hum180.connect(g180).connect(master);

    const wobble = ctx.createOscillator();
    wobble.type = 'sine';
    wobble.frequency.value = 2.2;
    const wobbleGain = ctx.createGain();
    wobbleGain.gain.value = Math.max(0.001, target * 0.065);
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

    return { master, sources };
  }

  function stopActive({ fade = true } = {}) {
    if (!active || !ctx) return;

    if (testTimer) {
      clearTimeout(testTimer);
      testTimer = null;
    }

    const playing = active;
    active = null;
    const now = ctx.currentTime;

    try {
      playing.master.gain.cancelScheduledValues(now);
      const current = Math.max(playing.master.gain.value || gainForVolume(settings.volume), 0.0001);
      playing.master.gain.setValueAtTime(current, now);
      if (fade) playing.master.gain.exponentialRampToValueAtTime(0.0001, now + 0.8);
      else playing.master.gain.setValueAtTime(0.0001, now);
    } catch (_) {}

    setTimeout(() => {
      for (const source of playing.sources) {
        try { source.stop(); } catch (_) {}
      }
    }, fade ? 900 : 30);

    testBtn.textContent = '🔊 Testar som do motor';
    testBtn.setAttribute('aria-pressed', 'false');
  }

  async function startAutomatic() {
    if (!settings.enabled || currentMotorState() !== 'running' || active?.mode === 'auto') return;
    if (!(await ensureAudio())) return;

    stopActive({ fade: false });
    active = { mode: 'auto', ...createMotorSound({ startup: true }) };
    setFeedback(`Som automático ativo · volume ${settings.volume}%.`);
  }

  function stopAutomatic() {
    if (active?.mode === 'auto') stopActive({ fade: true });
    if (settings.enabled) {
      setFeedback(currentMotorState() === 'running'
        ? 'Som habilitado. Interaja com a página para liberar o áudio do navegador.'
        : 'Som habilitado. Aguardando o motor ligar.');
    } else {
      setFeedback('Som automático desativado.');
    }
  }

  async function syncWithMotor() {
    if (!settings.enabled) {
      stopAutomatic();
      return;
    }

    if (currentMotorState() === 'running') {
      if (unlocked || ctx?.state === 'running') await startAutomatic();
      else setFeedback('Som habilitado. Interaja com a página para liberar o áudio do navegador.');
    } else {
      stopAutomatic();
    }
  }

  async function toggleTest() {
    if (active?.mode === 'test') {
      stopActive({ fade: true });
      await syncWithMotor();
      return;
    }

    if (!(await ensureAudio())) return;
    stopActive({ fade: false });

    active = { mode: 'test', ...createMotorSound({ startup: true }) };
    testBtn.textContent = '■ Parar teste de som';
    testBtn.setAttribute('aria-pressed', 'true');
    setFeedback(`Teste local · volume ${settings.volume}% · não envia comando ao motor.`);

    testTimer = setTimeout(async () => {
      if (active?.mode === 'test') stopActive({ fade: true });
      await syncWithMotor();
    }, 5000);
  }

  function applyLiveVolume() {
    if (!active || !ctx) return;
    const now = ctx.currentTime;
    const target = gainForVolume(settings.volume);
    try {
      active.master.gain.cancelScheduledValues(now);
      active.master.gain.setTargetAtTime(Math.max(target, 0.0001), now, 0.04);
    } catch (_) {}
  }

  enabledInput.checked = settings.enabled;
  volumeInput.value = String(settings.volume);
  updateVolumeDisplay();
  updateEnabledText();
  testBtn.setAttribute('aria-pressed', 'false');

  enabledInput.addEventListener('change', async () => {
    settings.enabled = enabledInput.checked;
    saveSettings();
    updateEnabledText();

    if (settings.enabled) {
      await ensureAudio();
      await syncWithMotor();
    } else {
      if (active?.mode === 'auto') stopActive({ fade: true });
      setFeedback('Som automático desativado.');
    }
  });

  volumeInput.addEventListener('input', () => {
    settings.volume = clampVolume(volumeInput.value);
    updateVolumeDisplay();
    saveSettings();
    applyLiveVolume();

    if (active?.mode === 'auto') setFeedback(`Som automático ativo · volume ${settings.volume}%.`);
    if (active?.mode === 'test') setFeedback(`Teste local · volume ${settings.volume}% · não envia comando ao motor.`);
  });

  testBtn.addEventListener('click', toggleTest);

  const observer = new MutationObserver(() => { syncWithMotor(); });
  observer.observe(motorVisual, { attributes: true, attributeFilter: ['data-state'] });

  const unlock = async () => {
    if (!settings.enabled || unlocked) return;
    if (await ensureAudio()) await syncWithMotor();
  };
  window.addEventListener('pointerdown', unlock, { passive: true });
  window.addEventListener('keydown', unlock);

  if (settings.enabled) {
    setFeedback(currentMotorState() === 'running'
      ? 'Som habilitado. Interaja com a página para liberar o áudio do navegador.'
      : 'Som habilitado. Aguardando o motor ligar.');
  } else {
    setFeedback('Som automático desativado.');
  }

  window.iotmotorMotorSound = {
    sync: syncWithMotor,
    stop: () => stopActive({ fade: true }),
    settings: () => ({ ...settings }),
  };
})();