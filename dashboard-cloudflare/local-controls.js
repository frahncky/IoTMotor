'use strict';
// Partidas da bancada. A lista mora no ESP32-01 (tópico .../profiles) e é a
// mesma no painel e no app: criar ou editar aqui aparece lá, e vice-versa.
// Cada contator tem o instante em que liga e o instante em que desliga,
// contados do início da partida; "0" no desligar = fica ligado até parar.
(() => {
  const $ = id => document.getElementById(id);
  const painel = document.querySelector('.control');
  const start = $('startBtn'), stop = $('stopBtn');
  if (!painel || !start || !stop) return;
  window.iotmotorLocalControls = true;  // Os gráficos não mexem nestes botões.
  start.disabled = true;
  stop.disabled = true;

  const CONTATORES = [1, 2, 3, 4];
  let client = null, conectado = false, prefixo = '', dispositivo = '';
  let perfis = [], limiteMs = 300000, maximo = 6, selecionado = '', pendente = null, sequencia = 0;

  const topico = tipo => `${prefixo}/${dispositivo}/${tipo}`;
  const aviso = texto => { const el = $('commandFeedback'); if (el) el.textContent = texto; };
  const segundos = ms => (ms / 1000).toLocaleString('pt-BR', {maximumFractionDigits: 1});

  const caixa = document.createElement('section');
  caixa.style.cssText = 'border:1px solid #50778a;border-radius:12px;padding:16px;background:#0a2936;margin:14px 0 4px';
  caixa.innerHTML = `<div class="field"><label for="startProfile">Partida</label><select id="startProfile" style="padding:9px;background:#102e3b;color:white;border:1px solid #608697;border-radius:8px;width:100%"></select></div>
    <p class="muted" id="profileResumo" style="margin:10px 0 0">Conecte ao MQTT para ver as partidas gravadas na placa.</p>
    <div class="buttons" style="margin:12px 0 0"><button class="btn secondary" type="button" id="profileNovo" disabled>Nova partida</button><button class="btn secondary" type="button" id="profileEditar" disabled>Editar</button><button class="btn secondary" type="button" id="profileRemover" disabled>Remover</button></div>`;
  painel.querySelector('.buttons').before(caixa);

  const dialogo = document.createElement('dialog');
  dialogo.id = 'profileDialog';
  dialogo.style.cssText = 'border:1px solid #365968;border-radius:16px;background:#102b39;color:#f0f7fa;max-width:560px;width:92vw;padding:20px';
  dialogo.innerHTML = `<form method="dialog"><h3 style="margin:0 0 6px">Partida</h3>
    <p class="muted" style="margin:0 0 14px">Marque os contatores e informe, em segundos, quando cada um liga e desliga. Desligar em <strong>0</strong> = fica ligado até parar.</p>
    <div class="field"><label for="profileNome">Nome</label><input id="profileNome" maxlength="24" required style="width:100%;padding:10px 12px;background:#092430;color:#fff;border:1px solid #507183;border-radius:9px"></div>
    <table style="width:100%;margin-top:14px;border-collapse:collapse;font-size:14px"><thead><tr><th style="text-align:left;padding:6px 4px">Contator</th><th style="text-align:left;padding:6px 4px">Liga (s)</th><th style="text-align:left;padding:6px 4px">Desliga (s)</th></tr></thead><tbody id="profileLinhas"></tbody></table>
    <p class="feedback" id="profileErro" style="margin-top:14px">&nbsp;</p>
    <div class="buttons" style="justify-content:flex-end"><button class="btn secondary" type="button" id="profileCancelar">Cancelar</button><button class="btn" type="button" id="profileSalvar">Salvar na placa</button></div></form>`;
  document.body.append(dialogo);

  for (const n of CONTATORES) {
    const linha = document.createElement('tr');
    linha.innerHTML = `<td style="padding:6px 4px"><label style="display:inline-flex;align-items:center;gap:6px"><input type="checkbox" id="usa${n}"> CNT ${n}</label></td>
      <td style="padding:6px 4px"><input type="number" id="liga${n}" min="0" max="300" step="0.1" value="0.5" style="width:96px;padding:8px;background:#092430;color:#fff;border:1px solid #507183;border-radius:8px"></td>
      <td style="padding:6px 4px"><input type="number" id="desliga${n}" min="0" max="300" step="0.1" value="0" style="width:96px;padding:8px;background:#092430;color:#fff;border:1px solid #507183;border-radius:8px"></td>`;
    $('profileLinhas').append(linha);
  }

  function perfilSelecionado() {
    return perfis.find(p => p.id === selecionado) || null;
  }

  function resumo(perfil) {
    if (!perfil) return '';
    const partes = perfil.cnt.map((c, i) => c.use
      ? `CNT ${i + 1}: ${segundos(c.on)}s${c.off ? ` a ${segundos(c.off)}s` : ' até parar'}`
      : null).filter(Boolean);
    return partes.length ? partes.join(' · ') : 'Nenhum contator marcado.';
  }

  function renderizar() {
    const selecao = $('startProfile');
    const anterior = selecionado;
    selecao.replaceChildren(...perfis.map(p => {
      const opcao = document.createElement('option');
      opcao.value = p.id;
      opcao.textContent = p.name;
      return opcao;
    }));
    if (!perfis.some(p => p.id === anterior)) selecionado = perfis[0]?.id || '';
    selecao.value = selecionado;
    selecao.disabled = !perfis.length;
    $('profileResumo').textContent = perfis.length
      ? resumo(perfilSelecionado())
      : (conectado ? 'A placa ainda não publicou as partidas.' : 'Conecte ao MQTT para ver as partidas gravadas na placa.');
    const livre = conectado && !pendente;
    $('profileNovo').disabled = !livre || perfis.length >= maximo;
    $('profileEditar').disabled = !livre || !perfis.length;
    $('profileRemover').disabled = !livre || perfis.length <= 1;
  }

  function abrirEditor(perfil) {
    $('profileNome').value = perfil?.name || '';
    $('profileErro').textContent = ' ';
    for (const n of CONTATORES) {
      const c = perfil?.cnt?.[n - 1];
      $(`usa${n}`).checked = c ? c.use === true : n === 1;
      $(`liga${n}`).value = c ? c.on / 1000 : 0.5;
      $(`desliga${n}`).value = c ? c.off / 1000 : 0;
    }
    dialogo.dataset.id = perfil?.id || '';
    dialogo.showModal();
  }

  // Devolve o perfil pronto para a placa ou uma mensagem de erro.
  function lerEditor() {
    const nome = $('profileNome').value.trim();
    if (!nome) return {erro: 'Informe o nome da partida.'};
    // A placa guarda o nome em 24 bytes, e cada acento ocupa dois: sem esta
    // conta, um nome acentuado perto do limite era recusado sem explicação.
    const bytes = new TextEncoder().encode(nome).length;
    if (bytes > 24) {
      return {erro: `Nome comprido para a placa (${bytes} de 24; cada acento conta dois).`};
    }
    const cnt = CONTATORES.map(n => ({
      use: $(`usa${n}`).checked,
      on: Math.round(Number($(`liga${n}`).value) * 1000),
      off: Math.round(Number($(`desliga${n}`).value) * 1000)
    }));
    if (!cnt.some(c => c.use)) return {erro: 'Marque pelo menos um contator.'};
    for (const [i, c] of cnt.entries()) {
      if (!c.use) continue;
      if (!Number.isFinite(c.on) || c.on < 0 || c.on > limiteMs)
        return {erro: `CNT ${i + 1}: ligar entre 0 e ${segundos(limiteMs)} s.`};
      if (!Number.isFinite(c.off) || c.off < 0 || c.off > limiteMs)
        return {erro: `CNT ${i + 1}: desligar entre 0 e ${segundos(limiteMs)} s.`};
      if (c.off && c.off <= c.on)
        return {erro: `CNT ${i + 1}: desligar depois de ligar (ou 0 para ficar ligado).`};
    }
    const id = dialogo.dataset.id ||
      `p${Date.now().toString(36).slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
    return {perfil: {id, name: nome, cnt}};
  }

  function publicar(acao, extras, mensagem) {
    if (!client?.connected) { aviso('Sem conexão com o broker.'); return false; }
    const impede = window.iotmotorSelo?.impedimento(dispositivo);
    if (impede) { aviso(impede); return false; }
    const seq = String(sequencia = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequencia + 1));
    const ativo = client;
    pendente = {seq, acao};
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
      pendente = null; aviso('Não deu para selar o comando: ' + (erro.message || erro)); renderizar();
    });
    setTimeout(() => {
      if (pendente?.seq === seq) { pendente = null; aviso('Sem resposta do ESP32-01.'); renderizar(); }
    }, 8000);
    aviso(mensagem);
    renderizar();
    return true;
  }

  $('startProfile').addEventListener('change', () => {
    selecionado = $('startProfile').value;
    renderizar();
  });
  $('profileNovo').addEventListener('click', () => abrirEditor(null));
  $('profileEditar').addEventListener('click', () => abrirEditor(perfilSelecionado()));
  $('profileRemover').addEventListener('click', () => {
    const perfil = perfilSelecionado();
    if (perfil && confirm(`Remover a partida "${perfil.name}" da placa?`))
      publicar('profile_remove', {id: perfil.id}, `Removendo "${perfil.name}"…`);
  });
  $('profileCancelar').addEventListener('click', () => dialogo.close());
  $('profileSalvar').addEventListener('click', () => {
    const resultado = lerEditor();
    if (resultado.erro) { $('profileErro').textContent = resultado.erro; return; }
    if (publicar('profile_save', {profile: resultado.perfil}, `Gravando "${resultado.perfil.name}" na placa…`)) {
      selecionado = resultado.perfil.id;
      dialogo.close();
    }
  });

  // A partida escolhida é o que o botão Ligar envia (remote-controls.js).
  window.iotmotorPartidaSelecionada = () => selecionado;

  function conectar() {
    if (!window.mqtt?.connect) { aviso('Biblioteca MQTT indisponível.'); return; }
    let url, p, d;
    try {
      url = new URL(String($('broker').value || '').trim());
      if (url.protocol !== 'wss:') throw Error('Use uma URL wss://.');
      p = String($('prefix').value || 'iotmotor').trim().replace(/^\/+|\/+$/g, '');
      d = String($('commandDevice').value || 'esp32-01').trim();
      if (!/^[a-zA-Z0-9_-]+$/.test(d)) throw Error('ID do ESP32-01 inválido.');
    } catch (e) { aviso(e.message); return; }
    if (client) client.end(true);
    prefixo = p; dispositivo = d; perfis = []; pendente = null;
    const ativo = window.mqtt.connect(url.toString(), {
      clientId: `iotmotor_perfis_${Math.random().toString(36).slice(2, 12)}`,
      clean: true, reconnectPeriod: 4000, connectTimeout: 10000, protocolVersion: 4, keepalive: 30
    });
    client = ativo;
    ativo.on('connect', () => {
      if (client !== ativo) return;
      conectado = true;
      ativo.subscribe([topico('profiles'), topico('command_ack'), topico('telemetry'), topico('auth')], {qos: 1});
      renderizar();
    });
    ativo.on('message', (nome, payload) => {
      if (client !== ativo) return;
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (dados?.device_id !== dispositivo) return;
      if (nome === topico('auth')) {  // Desafio da placa, retido.
        window.iotmotorSelo?.registrarAuth(dispositivo, dados);
        renderizar();
        return;
      }
      if (nome === topico('profiles')) {
        if (!Array.isArray(dados.profiles)) return;
        perfis = dados.profiles.filter(p => p && typeof p.id === 'string' && Array.isArray(p.cnt) && p.cnt.length === 4);
        limiteMs = Number(dados.limit_ms) || limiteMs;
        maximo = Number(dados.max) || maximo;
      } else if (nome === topico('telemetry')) {
        // Partida em andamento: o seletor segue a placa, mesmo que o comando
        // tenha vindo do app ou de outro navegador.
        const rodando = typeof dados.profile === 'string' ? dados.profile : '';
        if (rodando && rodando !== selecionado && perfis.some(p => p.id === rodando)) {
          selecionado = rodando;
          aviso(`Partida em andamento na placa: ${perfis.find(p => p.id === rodando).name}.`);
        } else if (!rodando) {
          return;  // Parada: mantem a escolha do usuario.
        }
      } else if (pendente && dados.seq === pendente.seq) {
        aviso((dados.accepted ? 'Placa confirmou: ' : 'Placa recusou: ') + (dados.reason || dados.action));
        pendente = null;
      }
      renderizar();
    });
    // Mesma tolerancia dos botoes Ligar/Desligar: quedas curtas do broker
    // publico nao devem apagar a lista de partidas da tela.
    let quedaTimer = null;
    const caiu = () => {
      if (client !== ativo || quedaTimer) return;
      quedaTimer = setTimeout(() => {
        quedaTimer = null;
        if (client !== ativo || ativo.connected) return;
        conectado = false;
        renderizar();
      }, 6000);
    };
    ativo.on('offline', caiu);
    ativo.on('close', caiu);
    ativo.on('reconnect', caiu);
    ativo.on('connect', () => { if (quedaTimer) { clearTimeout(quedaTimer); quedaTimer = null; } });
    renderizar();
  }

  function desconectar() {
    if (client) client.end(true);
    client = null; conectado = false; pendente = null;
    window.iotmotorSelo?.esquecer(dispositivo);
    renderizar();
  }

  window.iotmotorPerfis = {connect: conectar, disconnect: desconectar};
  renderizar();
})();
