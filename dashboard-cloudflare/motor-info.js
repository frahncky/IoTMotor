'use strict';
// Dados de placa do motor, gravados no quadro de comando (esp32-01): o painel
// e o app leem os mesmos valores. Todos opcionais; sem a corrente nominal o
// painel apenas não mostra a carga em %.
(() => {
  const $ = id => document.getElementById(id);
  if (!$('motorInfoForm')) return;

  // Campo do formulário -> campo no MQTT, com a faixa aceita pela placa.
  const CAMPOS = [
    {id: 'motorInfoCv', chave: 'power_cv', max: 3000},
    {id: 'motorInfoV', chave: 'voltage_v', max: 1000},
    {id: 'motorInfoA', chave: 'current_a', max: 2000},
    {id: 'motorInfoRpm', chave: 'rpm', max: 10000},
    {id: 'motorInfoFs', chave: 'service_factor', min: 1, max: 3}
  ];

  let client = null, conectado = false, prefixo = '', dispositivo = 'esp32-01';
  let info = null, pendente = null, sequencia = 0, editando = false;
  const aviso = texto => { $('motorInfoFeedback').textContent = texto; };
  const topico = tipo => `${prefixo}/${dispositivo}/${tipo}`;

  // Aceita vírgula decimal; vazio = não cadastrado.
  function lerCampo(campo) {
    const texto = String($(campo.id).value || '').trim().replace(',', '.');
    if (!texto) return {valor: null};
    const n = Number(texto);
    const minimo = campo.min ?? 0;
    if (!Number.isFinite(n) || n < 0 || n > campo.max || (n > 0 && n < minimo))
      return {erro: `${$(campo.id).labels?.[0]?.textContent || campo.chave}: use de ${minimo} a ${campo.max}.`};
    return {valor: n > 0 ? n : null};
  }

  function preencher() {
    if (editando || pendente) return;
    for (const campo of CAMPOS) {
      const v = info?.[campo.chave];
      $(campo.id).value = Number.isFinite(v) ? String(v) : '';
    }
    $('motorInfoFases').value = info?.phases === 1 || info?.phases === 3 ? String(info.phases) : '';
  }

  function renderizar() {
    const pronto = conectado && !pendente;
    $('motorInfoSalvar').disabled = !pronto;
    $('motorInfoZerar').disabled = !pronto;
    $('motorInfoCargaDica').hidden = Number.isFinite(info?.current_a);
  }

  function limparPendente() {
    if (pendente?.timer) clearTimeout(pendente.timer);
    pendente = null;
  }

  function publicar(acao, extras) {
    if (!client?.connected || !conectado) { aviso('Sem conexão com o broker.'); return false; }
    const impede = window.iotmotorSelo?.impedimento(dispositivo);
    if (impede) { aviso(impede); return false; }
    const seq = String(sequencia = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequencia + 1));
    const ativo = client;
    pendente = {seq, acao};
    pendente.timer = setTimeout(() => {
      if (client !== ativo || pendente?.seq !== seq) return;
      limparPendente(); aviso('Sem resposta do quadro de comando. Ele está online?'); renderizar();
    }, 8000);
    // O comando sai cifrado quando a placa exige senha (command-seal.js).
    const comando = {v: 1, device_id: dispositivo, seq, action: acao, ...extras};
    const selo = window.iotmotorSelo;
    const enviar = texto => {
      if (client === ativo && pendente?.seq === seq)
        client.publish(topico('command'), texto, {qos: 1, retain: false});
    };
    const aberto = selo ? selo.empacotarAberto(dispositivo, comando) : JSON.stringify(comando);
    if (aberto !== null) enviar(aberto);
    else selo.empacotar(dispositivo, comando).then(enviar).catch(erro => {
      if (client !== ativo || pendente?.seq !== seq) return;
      limparPendente(); aviso('Não deu para selar o comando: ' + (erro.message || erro)); renderizar();
    });
    renderizar();
    return true;
  }

  function desconectar() {
    const antigo = client;
    client = null; conectado = false; info = null; editando = false;
    limparPendente();
    if (antigo) antigo.end(true);
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
      d = String($('commandDevice').value || '').trim();
      if (!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(p)) throw Error('Prefixo inválido.');
      if (!/^[a-zA-Z0-9_-]+$/.test(d)) throw Error('ID do quadro de comando inválido.');
    } catch (e) { aviso(e.message); return; }
    prefixo = p; dispositivo = d;
    let ativo;
    try {
      ativo = window.mqtt.connect(url.toString(), {
        clientId: `iotmotor_motorinfo_${Math.random().toString(36).slice(2, 12)}`,
        clean: true, reconnectPeriod: 4000, connectTimeout: 10000, protocolVersion: 4, keepalive: 30
      });
    } catch (e) { aviso(e.message); return; }
    client = ativo;
    ativo.on('connect', () => {
      if (client !== ativo) return;
      ativo.subscribe([topico('motor_info'), topico('command_ack'), topico('auth')], {qos: 1}, erro => {
        if (client !== ativo) return;
        conectado = !erro;
        aviso(conectado ? 'Conectado ao quadro de comando.' : 'Falha ao assinar os tópicos do quadro.');
        renderizar();
      });
    });
    ativo.on('message', (nome, payload) => {
      if (client !== ativo) return;
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (dados?.device_id !== dispositivo) return;
      if (nome === topico('auth')) { window.iotmotorSelo?.registrarAuth(dispositivo, dados); return; }
      // Retido: chega assim que assinamos, e de novo a cada gravação.
      if (nome === topico('motor_info')) {
        info = {};
        for (const campo of CAMPOS) if (Number.isFinite(dados[campo.chave])) info[campo.chave] = dados[campo.chave];
        if (dados.phases === 1 || dados.phases === 3) info.phases = dados.phases;
        preencher();
        renderizar();
        return;
      }
      if (nome === topico('command_ack') && pendente && dados.seq === pendente.seq) {
        aviso((dados.accepted ? 'Placa confirmou: ' : 'Placa recusou: ') + (dados.reason || dados.action));
        if (dados.accepted) editando = false;
        limparPendente();
        preencher();
        renderizar();
      }
    });
    ativo.on('error', erro => { if (client === ativo) aviso(`MQTT: ${erro.message || erro}`); });
    renderizar();
  }

  for (const campo of CAMPOS) $(campo.id).addEventListener('input', () => { editando = true; });
  $('motorInfoFases').addEventListener('change', () => { editando = true; });
  $('motorInfoForm').addEventListener('submit', evento => {
    evento.preventDefault();
    const motor = {};
    for (const campo of CAMPOS) {
      const lido = lerCampo(campo);
      if (lido.erro) { aviso(lido.erro); return; }
      if (lido.valor !== null) motor[campo.chave] = lido.valor;
    }
    const fases = Number($('motorInfoFases').value);
    if (fases === 1 || fases === 3) motor.phases = fases;  // Monofásico ou trifásico.
    if (publicar('motor_info_set', {motor})) aviso('Gravando os dados do motor na placa…');
  });
  $('motorInfoZerar').addEventListener('click', () => {
    if (!confirm('Zerar o horímetro e o contador de partidas do quadro de comando?\n\n' +
                 'Use ao trocar de motor. O motor precisa estar parado.')) return;
    if (publicar('motor_counters_reset', {})) aviso('Zerando horímetro e partidas…');
  });

  window.iotmotorMotorInfo = {
    connect: conectar,
    disconnect: desconectar,
    // Cópia dos dados de placa (null enquanto a placa não publicou).
    dados: () => (info ? {...info} : null)
  };
  renderizar();
})();
