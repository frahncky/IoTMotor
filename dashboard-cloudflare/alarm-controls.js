'use strict';
// O S3 decide o alarme localmente; o painel configura limites e solicita o teste.
(() => {
  const $ = id => document.getElementById(id);
  if (!$('alarmeForm')) return;

  const CAMPOS = ['alarmeVib', 'alarmeTemp', 'alarmeOn'];
  let client = null, conectado = false, prefixo = '', dispositivo = 'esp32-02';
  let estado = null, recebidoEm = 0, pendente = null, sequencia = 0, editando = false;
  const aviso = texto => { $('alarmeFeedback').textContent = texto; };
  const topico = tipo => `${prefixo}/${dispositivo}/${tipo}`;
  const recente = () => conectado && estado && Date.now() - recebidoEm < 10000;

  function renderizar() {
    const selo = $('alarmeEstado');
    let mensagem = conectado ? 'aguardando o S3' : 'sem sinal', classe = '';
    if (conectado && estado && !recente()) {
      mensagem = 'S3 sem dados recentes'; classe = 'wait';
    } else if (recente()) {
      if (!estado.enabled) { mensagem = 'alarme desligado'; classe = 'wait'; }
      else if (estado.active) { mensagem = 'ALARME: limite ultrapassado'; classe = 'error'; }
      else if (!estado.sensors) { mensagem = 'sem sensores válidos'; classe = 'wait'; }
      else { mensagem = 'normal'; classe = 'live'; }
    }
    selo.textContent = mensagem;
    selo.className = `source ${classe}`.trim();
    // Um rascunho permanece intacto mesmo depois de sair do campo.
    if (estado && !editando && !pendente) {
      $('alarmeVib').value = estado.vibration;
      $('alarmeTemp').value = estado.temperature;
      $('alarmeOn').checked = estado.enabled;
    }
    for (const id of CAMPOS) $(id).disabled = Boolean(pendente);
    $('alarmeSalvar').disabled = !recente() || Boolean(pendente);
    $('alarmeTeste').disabled = !recente() || Boolean(pendente);
  }

  for (const id of CAMPOS) {
    for (const evento of ['input', 'change'])
      $(id).addEventListener(evento, () => { editando = true; });
  }

  function limparPendente() {
    if (pendente) clearTimeout(pendente.timer);
    pendente = null;
  }

  function publicar(acao, extras) {
    if (!client?.connected || !recente()) { aviso('Aguarde dados recentes do ESP32-S3.'); return false; }
    if (pendente) return false;
    const seq = String(sequencia = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequencia + 1));
    const ativo = client;
    pendente = {seq, acao, extras};
    const falhou = erro => {
      if (!erro || client !== ativo || pendente?.seq !== seq) return;
      limparPendente(); aviso(`Falha ao enviar: ${erro.message || erro}`); renderizar();
    };
    pendente.timer = setTimeout(() => {
      if (client !== ativo || pendente?.seq !== seq) return;
      limparPendente(); aviso(`Sem resposta do ${dispositivo}.`); renderizar();
    }, 8000);
    try {
      client.publish(topico('command'), JSON.stringify({
        v: 1, device_id: dispositivo, seq, action: acao, ...extras
      }), {qos: 1, retain: false}, falhou);
    } catch (erro) { falhou(erro); }
    renderizar();
    return pendente?.seq === seq;
  }

  $('alarmeForm').addEventListener('submit', evento => {
    evento.preventDefault();
    const vib = Number($('alarmeVib').value), temp = Number($('alarmeTemp').value);
    if (!Number.isFinite(vib) || vib < 0.02 || vib > 8) { aviso('Vibração: informe de 0,02 a 8 g.'); return; }
    if (!Number.isFinite(temp) || temp < 1 || temp > 125) { aviso('Temperatura: informe de 1 a 125 °C.'); return; }
    if (publicar('alarm_set', {enabled: $('alarmeOn').checked, vibration_limit: vib, temperature_limit: temp}))
      aviso('Gravando os limites no S3…');
  });
  $('alarmeTeste').addEventListener('click', () => {
    if (publicar('alarm_test', {})) aviso('Acendendo o LED e apitando por 1,5 s…');
  });

  function desconectar() {
    const antigo = client;
    client = null; conectado = false; estado = null; recebidoEm = 0; editando = false;
    limparPendente();
    if (antigo) antigo.end(true);
    aviso('Conecte ao MQTT para ajustar o alarme.');
    renderizar();
  }

  function conectar() {
    desconectar();
    if (!window.mqtt?.connect) { aviso('Biblioteca MQTT indisponível.'); return; }
    let url, p, d;
    try {
      url = new URL(String($('broker').value || '').trim());
      if (url.protocol !== 'wss:' || !url.hostname || url.username || url.password || url.search || url.hash)
        throw Error('Informe uma URL wss:// válida, sem credenciais.');
      p = String($('prefix').value || '').trim().replace(/^\/+|\/+$/g, '');
      d = String($('sensorDevice').value || '').trim();
      if (!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(p)) throw Error('Prefixo inválido.');
      if (!/^[a-zA-Z0-9_-]+$/.test(d)) throw Error('ID do ESP32-S3 inválido.');
    } catch (e) { aviso(e.message); return; }
    prefixo = p; dispositivo = d;
    let ativo;
    try {
      ativo = window.mqtt.connect(url.toString(), {
        clientId: `iotmotor_alarme_${Math.random().toString(36).slice(2, 12)}`,
        clean: true, reconnectPeriod: 4000, connectTimeout: 10000, protocolVersion: 4, keepalive: 30
      });
    } catch (e) { aviso(e.message); return; }
    client = ativo;
    ativo.on('connect', () => {
      if (client !== ativo) return;
      estado = null; recebidoEm = 0; conectado = false;
      ativo.subscribe([topico('telemetry'), topico('command_ack'), topico('status')], {qos: 1}, (erro, permissoes) => {
        if (client !== ativo || !ativo.connected) return;
        conectado = !erro && !permissoes?.some(p => p.qos === 128);
        aviso(conectado ? 'Conectado. Aguardando a telemetria do ESP32-S3.' : 'Falha ao assinar os tópicos do alarme.');
        renderizar();
      });
    });
    ativo.on('message', (nome, payload, pacote) => {
      if (client !== ativo || !conectado) return;
      if (nome === topico('status')) {
        if (!pacote?.retain && payload.toString('utf8').trim() === 'offline') {
          estado = null; recebidoEm = 0; limparPendente();
          aviso('ESP32-S3 desconectado.'); renderizar();
        }
        return;
      }
      if (pacote?.retain) return;
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (dados?.device_id !== dispositivo) return;
      if (nome === topico('telemetry')) {
        if (typeof dados.alarm_enabled !== 'boolean' || typeof dados.alarm_active !== 'boolean' ||
            typeof dados.mpu_ok !== 'boolean' || typeof dados.temperature_ok !== 'boolean' ||
            !Number.isFinite(dados.vibration_limit) || dados.vibration_limit < 0.02 || dados.vibration_limit > 8 ||
            !Number.isFinite(dados.temperature_limit) || dados.temperature_limit < 1 || dados.temperature_limit > 125) return;
        estado = {
          enabled: dados.alarm_enabled, active: dados.alarm_active,
          vibration: dados.vibration_limit, temperature: dados.temperature_limit,
          sensors: dados.mpu_ok || dados.temperature_ok
        };
        recebidoEm = Date.now();
      } else if (nome === topico('command_ack') && pendente && dados.seq === pendente.seq &&
                 dados.action === pendente.acao && typeof dados.accepted === 'boolean') {
        if (dados.accepted && pendente.acao === 'alarm_set') {
          estado = {...estado, enabled: pendente.extras.enabled,
            vibration: pendente.extras.vibration_limit, temperature: pendente.extras.temperature_limit};
          editando = false;
        }
        aviso((dados.accepted ? 'S3 confirmou: ' : 'S3 recusou: ') + (dados.reason || dados.action));
        limparPendente();
      }
      renderizar();
    });
    const caiu = () => {
      if (client !== ativo) return;
      conectado = false; estado = null; recebidoEm = 0;
      limparPendente(); aviso('Conexão interrompida. Aguardando reconexão.'); renderizar();
    };
    ativo.on('offline', caiu);
    ativo.on('close', caiu);
    ativo.on('error', erro => { if (client === ativo) aviso(`MQTT: ${erro.message || erro}`); });
    renderizar();
  }

  window.iotmotorAlarme = {connect: conectar, disconnect: desconectar};
  setInterval(renderizar, 1000);
  renderizar();
})();