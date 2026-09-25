'use strict';
// O S3 decide o alarme localmente; o painel edita a lista gravada na placa.
//
// Cada alarme diz qual grandeza vigiar, se dispara acima ou abaixo e o limite.
// As grandezas elétricas vêm do quadro de comando: o S3 assina a telemetria
// dele, então tensão e corrente disparam o mesmo LED e o mesmo buzzer.
(() => {
  const $ = id => document.getElementById(id);
  if (!$('alarmeForm')) return;

  // Grandezas oferecidas, com a placa de origem e a faixa aceita no formulário.
  const GRANDEZAS = [
    {campo: 'vibration_peak', placa: 'sensors', nome: 'Vibração (pico)', unidade: 'g', min: 0.02, max: 8, passo: 0.01},
    {campo: 'vibration', placa: 'sensors', nome: 'Vibração (RMS)', unidade: 'g', min: 0.01, max: 8, passo: 0.01},
    {campo: 'temperature', placa: 'sensors', nome: 'Temperatura', unidade: '°C', min: 1, max: 125, passo: 1},
    {campo: 'voltage', placa: 'command', nome: 'Tensão', unidade: 'V', min: 0, max: 600, passo: 1},
    {campo: 'current', placa: 'command', nome: 'Corrente', unidade: 'A', min: 0, max: 200, passo: 0.1},
    {campo: 'power', placa: 'command', nome: 'Potência', unidade: 'W', min: 0, max: 50000, passo: 10},
    {campo: 'frequency', placa: 'command', nome: 'Frequência', unidade: 'Hz', min: 0, max: 120, passo: 0.5},
    {campo: 'pf', placa: 'command', nome: 'Fator de potência', unidade: '', min: 0, max: 1, passo: 0.01}
  ];
  const grandezaDe = campo => GRANDEZAS.find(g => g.campo === campo);
  const rotulo = campo => {
    const g = grandezaDe(campo);
    return g ? `${g.nome}${g.unidade ? ` (${g.unidade})` : ''}` : campo;
  };

  const CAMPOS = ['alarmeOn', 'alarmeSons'];
  let client = null, conectado = false, prefixo = '', dispositivo = 'esp32-02';
  let estado = null, recebidoEm = 0, pendente = null, sequencia = 0, editando = false;
  let lista = null, maxAlarmes = 8;
  const rascunhos = new Map();  // id -> {limite, ligado} ainda não gravados.
  const aviso = texto => { $('alarmeFeedback').textContent = texto; };
  const topico = tipo => `${prefixo}/${dispositivo}/${tipo}`;
  const recente = () => conectado && estado && Date.now() - recebidoEm < 10000;
  const pronto = () => recente() && !pendente;

  function preencherGrandezas() {
    const select = $('alarmeGrandeza');
    if (select.options?.length) return;
    for (const g of GRANDEZAS) {
      const op = document.createElement('option');
      op.value = g.campo;
      op.textContent = `${rotulo(g.campo)} — ${g.placa === 'command' ? 'quadro de comando' : 'sensores do motor'}`;
      select.append(op);
    }
  }

  // Um id curto e estável, derivado da grandeza (a placa aceita até 12 letras).
  function novoId(campo) {
    const base = campo.replace(/[^a-z]/g, '').slice(0, 8) || 'alarme';
    const usados = new Set((lista || []).map(a => a.id));
    if (!usados.has(base)) return base;
    for (let i = 2; i < 99; i++) if (!usados.has(base + i)) return base + i;
    return base + Date.now().toString(36).slice(-3);
  }

  const alarmeValido = a => a && typeof a.id === 'string' && a.id &&
    typeof a.field === 'string' && a.field && Number.isFinite(a.limit);

  function guardarRascunho(alarme, mudanca) {
    const atual = rascunhos.get(alarme.id) ||
      {limite: String(alarme.limit), ligado: alarme.on !== false};
    rascunhos.set(alarme.id, {...atual, ...mudanca});
  }

  // O painel principal é somente leitura: mostra apenas condições disparadas.
  // Toda edição permanece isolada na aba "Configuração de alarmes".
  function desenharAtivos() {
    const alvo = $('alarmeAtivosLista');
    const resumo = $('alarmeAtivosResumo');
    if (!alvo || !resumo) return;
    alvo.replaceChildren();

    let mensagem = 'Conecte ao MQTT para acompanhar os alarmes ativos.';
    if (conectado && !recente()) mensagem = 'Sem dados recentes dos sensores.';
    else if (recente() && !estado.enabled) mensagem = 'O monitoramento de alarmes está desligado.';

    const disparados = recente() && estado.enabled ? [...new Set(estado.firing || [])] : [];
    if (disparados.length) {
      mensagem = `${disparados.length} ${disparados.length === 1 ? 'alarme ativo' : 'alarmes ativos'} neste momento.`;
      for (const id of disparados) {
        const alarme = (lista || []).find(item => item.id === id);
        const item = document.createElement('li');
        item.className = 'atual';
        const nome = document.createElement('span');
        nome.className = 'nome';
        nome.textContent = alarme
          ? `${rotulo(alarme.field)} ${alarme.above === false ? 'abaixo de' : 'acima de'} ${alarme.limit}`
          : `Alarme ${id}`;
        const estadoAtual = document.createElement('span');
        estadoAtual.className = 'tag on';
        estadoAtual.textContent = 'disparado';
        item.append(nome, estadoAtual);
        alvo.append(item);
      }
    } else if (recente() && estado.enabled) {
      mensagem = 'Nenhum alarme ativo.';
    }
    // Sem nada disparado a lista fica vazia: a frase aparece so no resumo.
    resumo.textContent = mensagem;
  }

  let listaDesenhada = '';

  // Tudo o que a lista mostra. Igual ao de antes, nao ha o que redesenhar.
  function assinaturaDaLista() {
    if (!lista) return 'sem-lista:' + String(conectado);
    return JSON.stringify([
      lista.map(a => [a.id, a.field, a.board, a.above, a.limit, a.on]),
      [...(estado?.firing || [])].sort(),
      [...rascunhos.entries()].sort(),
      pronto(), maxAlarmes
    ]);
  }

  function desenharLista() {
    const alvo = $('alarmeLista');
    const assinatura = assinaturaDaLista();
    if (assinatura === listaDesenhada) return;
    // Digitando: esperar. Trocar o campo agora apagaria o que foi escrito.
    const foco = document.activeElement;
    if (foco && alvo.contains?.(foco)) return;
    listaDesenhada = assinatura;
    alvo.replaceChildren();
    if (!lista) {
      $('alarmeResumo').textContent = conectado
        ? 'A placa ainda não publicou a lista de alarmes. Se estiver online, está com firmware antigo: atualize na aba Wi-Fi.'
        : 'Conecte ao MQTT para ver os alarmes gravados na placa.';
      return;
    }
    $('alarmeResumo').textContent = `${lista.length} de ${maxAlarmes} alarmes gravados na placa.`;
    if (!lista.length) {
      const vazio = document.createElement('li');
      vazio.className = 'vazio';
      vazio.textContent = 'Nenhum alarme cadastrado: a placa não vai acender nem apitar.';
      alvo.append(vazio);
      return;
    }
    const disparados = new Set(estado?.firing || []);
    for (const alarme of lista) {
      const rascunho = rascunhos.get(alarme.id);
      const g = grandezaDe(alarme.field);
      const item = document.createElement('li');
      if (disparados.has(alarme.id)) item.className = 'atual';

      const nome = document.createElement('span');
      nome.className = 'nome';
      nome.textContent = `${rotulo(alarme.field)} ${alarme.above === false ? 'abaixo de' : 'acima de'}`;
      item.append(nome);

      const limite = document.createElement('input');
      limite.className = 'limite';
      limite.type = 'number';
      limite.step = String(g?.passo ?? 'any');
      limite.value = rascunho ? rascunho.limite : String(alarme.limit);
      limite.setAttribute('aria-label', `Limite de ${rotulo(alarme.field)}`);
      limite.addEventListener('input', () => guardarRascunho(alarme, {limite: limite.value}));
      limite.addEventListener('blur', () => renderizar());
      item.append(limite);

      const origem = document.createElement('span');
      origem.className = 'tag';
      origem.textContent = alarme.board === 'command' ? 'quadro' : 'sensores';
      item.append(origem);

      if (disparados.has(alarme.id)) {
        const agora = document.createElement('span');
        agora.className = 'tag on';
        agora.textContent = 'disparado';
        item.append(agora);
      }

      const ligado = document.createElement('label');
      ligado.className = 'check';
      const marca = document.createElement('input');
      marca.type = 'checkbox';
      marca.checked = rascunho ? rascunho.ligado : alarme.on !== false;
      marca.addEventListener('change', () => guardarRascunho(alarme, {ligado: marca.checked}));
      ligado.append(marca, document.createTextNode(' ligado'));
      item.append(ligado);

      const ops = document.createElement('span');
      ops.className = 'ops';
      const botao = (texto, titulo, classe, acao) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.textContent = texto;
        b.title = titulo;
        if (classe) b.className = classe;
        b.disabled = !pronto();
        b.addEventListener('click', acao);
        ops.append(b);
      };
      botao('✓', 'Gravar este alarme na placa', '', () => gravarAlarme(alarme));
      botao('✕', 'Remover este alarme', 'del', () => removerAlarme(alarme));
      item.append(ops);
      alvo.append(item);
    }
  }

  function limiteAceito(campo, valor, texto) {
    const g = grandezaDe(campo);
    if (texto !== undefined && String(texto).trim() === '')
      return `${rotulo(campo)}: o campo está vazio.`;
    if (!Number.isFinite(valor)) return `Informe um número para ${rotulo(campo)}.`;
    if (g && (valor < g.min || valor > g.max))
      return `${rotulo(campo)}: informe de ${g.min} a ${g.max}.`;
    return '';
  }

  function gravarAlarme(alarme) {
    const rascunho = rascunhos.get(alarme.id);
    const texto = rascunho ? rascunho.limite : String(alarme.limit);
    const valor = Number(String(texto).replace(',', '.'));
    const erro = limiteAceito(alarme.field, valor, texto);
    if (erro) { aviso(erro); return; }
    const corpo = {
      id: alarme.id, field: alarme.field, board: alarme.board === 'command' ? 'command' : 'sensors',
      above: alarme.above !== false, limit: valor,
      on: rascunho ? rascunho.ligado : alarme.on !== false
    };
    if (publicar('alarm_save', {alarm: corpo}, alarme.id)) aviso('Gravando o alarme na placa…');
  }

  function removerAlarme(alarme) {
    if (publicar('alarm_remove', {id: alarme.id}, alarme.id)) aviso('Removendo o alarme…');
  }

  for (const id of CAMPOS) {
    for (const evento of ['input', 'change'])
      $(id).addEventListener(evento, () => { editando = true; });
  }

  function renderizar() {
    const selo = $('alarmeEstado');
    let mensagem = conectado ? 'aguardando os sensores' : 'sem sinal', classe = '';
    if (conectado && estado && !recente()) {
      mensagem = 'sem dados recentes'; classe = 'wait';
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
      $('alarmeOn').checked = estado.enabled;
      $('alarmeSons').checked = estado.sounds;
    }
    for (const id of CAMPOS) $(id).disabled = Boolean(pendente);
    for (const id of ['alarmeSalvar', 'alarmeTeste', 'alarmeBipe', 'alarmeProbe', 'alarmeRecarregar'])
      $(id).disabled = !pronto();
    $('alarmeAddBtn').disabled = !pronto() || !lista || lista.length >= maxAlarmes;
    desenharAtivos();
    desenharLista();
  }

  function limparPendente() {
    if (pendente) clearTimeout(pendente.timer);
    pendente = null;
  }

  function publicar(acao, extras, alvo) {
    if (!client?.connected || !recente()) { aviso('Aguarde dados recentes dos sensores.'); return false; }
    if (pendente) return false;
    const impede = window.iotmotorSelo?.impedimento(dispositivo);
    if (impede) { aviso(impede); return false; }
    const seq = String(sequencia = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequencia + 1));
    const ativo = client;
    pendente = {seq, acao, extras, alvo};
    const falhou = erro => {
      if (!erro || client !== ativo || pendente?.seq !== seq) return;
      limparPendente(); aviso(`Falha ao enviar: ${erro.message || erro}`); renderizar();
    };
    pendente.timer = setTimeout(() => {
      if (client !== ativo || pendente?.seq !== seq) return;
      limparPendente(); aviso(`Sem resposta do ${dispositivo}.`); renderizar();
    }, 8000);
    // O comando sai cifrado quando a placa exige senha (command-seal.js).
    const comando = {v: 1, device_id: dispositivo, seq, action: acao, ...extras};
    const selo = window.iotmotorSelo;
    const enviar = texto => {
      if (client !== ativo || pendente?.seq !== seq) return;
      try { client.publish(topico('command'), texto, {qos: 1, retain: false}, falhou); }
      catch (erro) { falhou(erro); }
    };
    const aberto = selo ? selo.empacotarAberto(dispositivo, comando) : JSON.stringify(comando);
    if (aberto !== null) enviar(aberto);
    else selo.empacotar(dispositivo, comando).then(enviar).catch(erro => falhou(erro));
    renderizar();
    return pendente?.seq === seq;
  }

  $('alarmeForm').addEventListener('submit', evento => {
    evento.preventDefault();
    if (publicar('alarm_set', {enabled: $('alarmeOn').checked, sounds: $('alarmeSons').checked}))
      aviso('Gravando a configuração na placa…');
  });
  $('alarmeAddForm').addEventListener('submit', evento => {
    evento.preventDefault();
    const campo = String($('alarmeGrandeza').value || '');
    const g = grandezaDe(campo);
    if (!g) { aviso('Escolha uma grandeza da lista.'); return; }
    const valor = Number(String($('alarmeLimite').value).replace(',', '.'));
    const erro = limiteAceito(campo, valor, $('alarmeLimite').value);
    if (erro) { aviso(erro); return; }
    const corpo = {
      id: novoId(campo), field: campo, board: g.placa,
      above: $('alarmeLado').value !== 'below', limit: valor, on: true
    };
    if (publicar('alarm_save', {alarm: corpo}, corpo.id)) aviso('Criando o alarme na placa…');
  });
  // A lista é retida, mas um pedido explícito resolve retenção perdida.
  $('alarmeRecarregar').addEventListener('click', () => {
    if (publicar('alarm_list', {})) aviso('Pedindo a lista de alarmes à placa…');
  });
  // Bipe curto: confirma na bancada que a placa esta ouvindo o painel.
  $('alarmeBipe').addEventListener('click', () => {
    if (publicar('buzzer_beep', {count: 2, ms: 120})) aviso('Bipando na placa de sensores…');
  });
  $('alarmeProbe').addEventListener('click', () => {
    if (publicar('buzzer_probe', {ms: 700})) aviso('Procurando o buzzer: ouça a placa e acompanhe os testes de GPIO…');
  });
  $('alarmeTeste').addEventListener('click', () => {
    if (publicar('alarm_test', {})) aviso('Acendendo o LED e apitando por 1,5 s…');
  });

  function desconectar() {
    const antigo = client;
    client = null; conectado = false; estado = null; recebidoEm = 0; editando = false;
    lista = null; rascunhos.clear(); listaDesenhada = '';
    window.iotmotorSelo?.esquecer(dispositivo);
    limparPendente();
    if (antigo) antigo.end(true);
    aviso('Conecte ao MQTT para ajustar o alarme.');
    renderizar();
  }

  function conectar() {
    desconectar();
    preencherGrandezas();
    if (!window.mqtt?.connect) { aviso('Biblioteca MQTT indisponível.'); return; }
    let url, p, d;
    try {
      url = new URL(String($('broker').value || '').trim());
      if (url.protocol !== 'wss:' || !url.hostname || url.username || url.password || url.search || url.hash)
        throw Error('Informe uma URL wss:// válida, sem credenciais.');
      p = String($('prefix').value || '').trim().replace(/^\/+|\/+$/g, '');
      d = String($('sensorDevice').value || '').trim();
      if (!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(p)) throw Error('Prefixo inválido.');
      if (!/^[a-zA-Z0-9_-]+$/.test(d)) throw Error('ID dos sensores inválido.');
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
      estado = null; recebidoEm = 0; conectado = false; lista = null;
      ativo.subscribe([topico('telemetry'), topico('command_ack'), topico('status'), topico('alarms'), topico('auth')],
        {qos: 1}, (erro, permissoes) => {
          if (client !== ativo || !ativo.connected) return;
          conectado = !erro && !permissoes?.some(p => p.qos === 128);
          aviso(conectado ? 'Conectado. Aguardando a telemetria dos sensores.' : 'Falha ao assinar os tópicos do alarme.');
          renderizar();
        });
    });
    ativo.on('message', (nome, payload, pacote) => {
      if (client !== ativo || !conectado) return;
      if (nome === topico('status')) {
        if (!pacote?.retain && payload.toString('utf8').trim() === 'offline') {
          estado = null; recebidoEm = 0; limparPendente();
          aviso('Placa de sensores desconectada.'); renderizar();
        }
        return;
      }
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (dados?.device_id !== dispositivo) return;
      // Desafio da placa, retido: sem ele não há como cifrar um comando.
      if (nome === topico('auth')) {
        window.iotmotorSelo?.registrarAuth(dispositivo, dados);
        renderizar();
        return;
      }
      // A lista de alarmes é retida: chega inteira assim que assinamos o tópico.
      if (nome === topico('alarms')) {
        if (!Array.isArray(dados.alarms)) return;
        lista = dados.alarms.filter(alarmeValido);
        maxAlarmes = Number.isFinite(dados.max) && dados.max > 0 ? dados.max : 8;
        for (const id of [...rascunhos.keys()]) if (!lista.some(a => a.id === id)) rascunhos.delete(id);
        renderizar();
        return;
      }
      if (pacote?.retain) return;
      if (nome === topico('telemetry')) {
        if (typeof dados.alarm_enabled !== 'boolean' || typeof dados.alarm_active !== 'boolean' ||
            typeof dados.mpu_ok !== 'boolean' || typeof dados.temperature_ok !== 'boolean') return;
        estado = {
          enabled: dados.alarm_enabled, active: dados.alarm_active,
          sounds: dados.event_sounds === true,
          sensors: dados.mpu_ok || dados.temperature_ok,
          firing: Array.isArray(dados.alarms_firing) ? dados.alarms_firing : []
        };
        recebidoEm = Date.now();
      } else if (nome === topico('command_ack') && pendente && dados.seq === pendente.seq &&
                 dados.action === pendente.acao && typeof dados.accepted === 'boolean') {
        if (dados.accepted && pendente.acao === 'alarm_set') {
          estado = {...estado, enabled: pendente.extras.enabled, sounds: pendente.extras.sounds};
          editando = false;
        }
        // Gravou: o rascunho some e a lista retida traz o valor confirmado.
        if (dados.accepted && pendente.alvo) rascunhos.delete(pendente.alvo);
        aviso((dados.accepted ? 'Placa confirmou: ' : 'Placa recusou: ') + (dados.reason || dados.action));
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
