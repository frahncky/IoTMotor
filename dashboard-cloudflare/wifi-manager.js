'use strict';
// Aba "Wi-Fi das placas": lista de redes gravada em cada ESP32, na ordem de
// prioridade definida aqui. Fala com as placas pelo mesmo broker MQTT.
//
// A senha NUNCA vai em texto aberto: a placa publica uma chave publica P-256
// no topico .../wifi; o navegador faz ECDH com uma chave efemera, deriva a
// chave AES-256 como SHA-256("iotmotor-wifi-v1" || segredo) e cifra a senha em
// AES-GCM usando o SSID como dado autenticado. Mesmo esquema de wifi_store.h.

const ROTULO_KDF = 'iotmotor-wifi-v1';

function paraBase64(dados) {
  const bytes = new Uint8Array(dados);
  let texto = '';
  for (const b of bytes) texto += String.fromCharCode(b);
  return btoa(texto);
}

function deBase64(texto) {
  return Uint8Array.from(atob(texto), c => c.charCodeAt(0));
}

// Cifra a senha para a chave publica da placa. Exportada para os testes.
async function cifrarSenha(chavePublicaB64, ssid, senha, cripto = globalThis.crypto) {
  const sutil = cripto.subtle;
  const chaveDaPlaca = await sutil.importKey('raw', deBase64(chavePublicaB64),
    {name: 'ECDH', namedCurve: 'P-256'}, false, []);
  const efemera = await sutil.generateKey({name: 'ECDH', namedCurve: 'P-256'}, true, ['deriveBits']);
  const segredo = new Uint8Array(await sutil.deriveBits({name: 'ECDH', public: chaveDaPlaca},
    efemera.privateKey, 256));
  const rotulo = new TextEncoder().encode(ROTULO_KDF);
  const material = new Uint8Array(rotulo.length + segredo.length);
  material.set(rotulo);
  material.set(segredo, rotulo.length);
  const chaveAes = await sutil.importKey('raw', await sutil.digest('SHA-256', material),
    'AES-GCM', false, ['encrypt']);
  const iv = cripto.getRandomValues(new Uint8Array(12));
  const cifrado = await sutil.encrypt({name: 'AES-GCM', iv, additionalData: new TextEncoder().encode(ssid)},
    chaveAes, new TextEncoder().encode(senha));
  return {
    epk: paraBase64(await sutil.exportKey('raw', efemera.publicKey)),
    iv: paraBase64(iv),
    ct: paraBase64(cifrado)
  };
}

if (typeof document !== 'undefined') (() => {
  const $ = id => document.getElementById(id);
  if (!$('painel-wifi')) return;

  // ---- abas ----
  const abas = [...document.querySelectorAll('.tabs [role="tab"]')];
  function mostrarAba(nome) {
    for (const aba of abas) {
      const ativa = aba.dataset.tab === nome;
      aba.setAttribute('aria-selected', String(ativa));
      aba.tabIndex = ativa ? 0 : -1;
      $('painel-' + aba.dataset.tab).hidden = !ativa;
    }
    try { localStorage.setItem('iotmotor_aba', nome); } catch {}
  }
  abas.forEach((aba, i) => {
    aba.addEventListener('click', () => mostrarAba(aba.dataset.tab));
    aba.addEventListener('keydown', e => {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      const proxima = abas[(i + (e.key === 'ArrowRight' ? 1 : abas.length - 1)) % abas.length];
      mostrarAba(proxima.dataset.tab);
      proxima.focus();
    });
  });
  try {
    const salva = localStorage.getItem('iotmotor_aba');
    if (abas.some(aba => aba.dataset.tab === salva)) mostrarAba(salva);
  } catch {}

  // ---- estado ----
  let client = null, connected = false, prefixo = '', dispositivos = ['esp32-01', 'esp32-02'];
  let selecionado = 0, sequencia = 0, pendente = null;
  const placas = {};  // device -> {pubkey, networks:[{ssid,open}], connected, max, em}
  // A lista de redes é retida: continua no broker depois que a placa cai. Sem
  // olhar o status, a aba dizia "conectada em ..." de uma placa desligada.
  const estados = {};  // device -> 'online' | 'offline'
  let ordemEditada = null;  // lista de SSIDs enquanto o usuario reordena

  const topico = (dev, tipo) => `${prefixo}/${dev}/${tipo}`;
  const atual = () => placas[dispositivos[selecionado]];
  const nomeDaPlaca = () => selecionado === 0 ? 'Quadro de comando' : 'Sensores do motor';
  const aviso = texto => { $('wifiFeedback').textContent = texto; };

  function lerConfiguracao() {
    const url = new URL(String($('broker').value || 'wss://test.mosquitto.org:8081').trim());
    const p = String($('prefix').value || 'iotmotor').trim().replace(/^\/+|\/+$/g, '');
    const d = [String($('commandDevice').value || 'esp32-01').trim(), String($('sensorDevice').value || 'esp32-02').trim()];
    if (url.protocol !== 'wss:' || url.username || url.password ||
        !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(p) || d.some(x => !/^[a-zA-Z0-9_-]+$/.test(x)))
      throw Error('Configuração MQTT inválida.');
    return {url: url.toString(), p, d};
  }

  function renderizar() {
    const dev = dispositivos[selecionado];
    $('wifiDev0').textContent = 'Quadro de comando';
    $('wifiDev1').textContent = 'Sensores do motor';
    $('wifiDev0').title = dispositivos[0];
    $('wifiDev1').title = dispositivos[1];
    $('wifiDev0').setAttribute('aria-pressed', String(selecionado === 0));
    $('wifiDev1').setAttribute('aria-pressed', String(selecionado === 1));
    const placa = atual();
    const lista = $('wifiList');
    const noAr = () => estados[dispositivos[selecionado]] !== 'offline';
    lista.replaceChildren();

    if (!connected) $('wifiStatus').textContent = 'Conecte ao MQTT (botão no topo) para ver e editar as redes.';
    else if (!placa) $('wifiStatus').textContent = `${nomeDaPlaca()} ainda não publicou a lista de redes. Se estiver online, ` +
      'está com firmware antigo: use "Atualizar firmware desta placa".';
    else if (!noAr()) $('wifiStatus').textContent =
      `${nomeDaPlaca()}: desligada ou fora da rede agora. O que aparece abaixo é a ` +
      `última informação recebida${placa.connected ? ` (estava em "${placa.connected}")` : ''}.`;
    else $('wifiStatus').textContent = placa.connected
      ? `${nomeDaPlaca()}: conectada em "${placa.connected}". ${placa.networks.length} de ${placa.max || 8} redes cadastradas.`
      : `${nomeDaPlaca()}: lista recebida, sem informar a rede atual. ${placa.networks.length} de ${placa.max || 8} redes cadastradas.`;

    const ordem = placa ? (ordemEditada || placa.networks.map(r => r.ssid)) : [];
    if (placa && !ordem.length) {
      const vazio = document.createElement('li');
      vazio.className = 'vazio';
      vazio.textContent = 'Nenhuma rede cadastrada.';
      lista.append(vazio);
    }
    ordem.forEach((ssid, i) => {
      const rede = placa.networks.find(r => r.ssid === ssid) || {ssid, open: false};
      const item = document.createElement('li');
      if (placa.connected === ssid && noAr()) item.className = 'atual';
      const nome = document.createElement('span');
      nome.className = 'nome';
      nome.textContent = ssid;
      const tipo = document.createElement('span');
      tipo.className = 'tag';
      tipo.textContent = rede.open ? 'aberta' : 'com senha';
      item.append(nome, tipo);
      if (placa.connected === ssid && noAr()) {
        const agora = document.createElement('span');
        agora.className = 'tag on';
        agora.textContent = 'conectada agora';
        item.append(agora);
      }
      const ops = document.createElement('span');
      ops.className = 'ops';
      const botao = (rotulo, titulo, acao, desabilitado, classe) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.textContent = rotulo;
        b.title = titulo;
        b.setAttribute('aria-label', `${titulo}: ${ssid}`);
        b.disabled = desabilitado || !connected || !noAr();
        if (classe) b.className = classe;
        b.addEventListener('click', acao);
        return b;
      };
      ops.append(
        botao('↑', 'Subir prioridade', () => mover(i, -1), i === 0),
        botao('↓', 'Descer prioridade', () => mover(i, 1), i === ordem.length - 1),
        botao('✕', 'Remover', () => remover(ssid), ordem.length <= 1 || Boolean(ordemEditada), 'del'));
      item.append(ops);
      lista.append(item);
    });

    const mudou = Boolean(placa && ordemEditada &&
      ordemEditada.join('\n') !== placa.networks.map(r => r.ssid).join('\n'));
    $('wifiSaveOrder').disabled = !connected || !mudou || Boolean(pendente) || !noAr();
    $('wifiUndoOrder').disabled = !mudou;
    $('wifiAddBtn').disabled = !connected || !placa || Boolean(pendente) || !noAr() ||
      (!$('wifiOpen').checked && !placa.pubkey);
    $('wifiPass').disabled = $('wifiOpen').checked;

    // Rede propria da placa (ponto de acesso).
    const ap = placa?.ap;
    $('apStatus').textContent = !placa ? '—' : ap
      ? `Rede da placa: "${ap.name}" · ${ap.open ? 'aberta (sem senha)' : 'protegida por senha'}.`
      : 'A placa não informou a rede própria (firmware antigo?).';
    if (ap && apMostrada !== dev + '|' + ap.name) {  // Preenche ao trocar de placa ou ao receber.
      apMostrada = dev + '|' + ap.name;
      $('apName').value = ap.name;
      $('apOpen').checked = ap.open;
    }
    $('apPass').disabled = $('apOpen').checked;
    const livre = connected && Boolean(placa) && !pendente && noAr();
    $('apSaveBtn').disabled = !livre || (!$('apOpen').checked && !placa.pubkey);
    $('apOpenNow').disabled = !livre;
    // Disponivel mesmo sem lista: e assim que uma placa com firmware antigo a recebe.
    $('wifiUpdateFw').disabled = !connected || Boolean(pendente) || !noAr();
  }
  let apMostrada = '';

  function mover(indice, passo) {
    const placa = atual();
    if (!placa) return;
    const ordem = (ordemEditada || placa.networks.map(r => r.ssid)).slice();
    const destino = indice + passo;
    if (destino < 0 || destino >= ordem.length) return;
    [ordem[indice], ordem[destino]] = [ordem[destino], ordem[indice]];
    ordemEditada = ordem;
    aviso('Ordem alterada. Clique em "Salvar ordem" para gravar na placa.');
    renderizar();
  }

  function publicar(acao, extras) {
    if (!client?.connected) { aviso('Sem conexão com o broker.'); return false; }
    const dev = dispositivos[selecionado];
    const impede = window.iotmotorSelo?.impedimento(dev);
    if (impede) { aviso(impede); return false; }
    const seq = String(sequencia = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequencia + 1));
    const ativo = client;
    pendente = {seq, dev, acao};
    // O comando sai cifrado quando a placa exige senha (command-seal.js).
    const comando = {v: 1, device_id: dev, seq, action: acao, boot: '', mode: 'none',
      mask: 0, main: 0, star: 0, delta: 0, seconds: 0, ...extras};
    const selo = window.iotmotorSelo;
    const enviar = texto => {
      if (client === ativo && pendente?.seq === seq)
        client.publish(topico(dev, 'command'), texto, {qos: 1, retain: false});
    };
    const aberto = selo ? selo.empacotarAberto(dev, comando) : JSON.stringify(comando);
    if (aberto !== null) enviar(aberto);
    else selo.empacotar(dev, comando).then(enviar).catch(erro => {
      if (client !== ativo || pendente?.seq !== seq) return;
      pendente = null; aviso('Não deu para selar o comando: ' + (erro.message || erro)); renderizar();
    });
    setTimeout(() => {
      if (pendente?.seq === seq) { pendente = null; aviso(`Sem resposta de ${nomeDaPlaca().toLowerCase()}. A placa está online?`); renderizar(); }
    }, 8000);
    renderizar();
    return true;
  }

  function remover(ssid) {
    if (!confirm(`Remover a rede "${ssid}" de ${nomeDaPlaca()}?`)) return;
    if (publicar('wifi_remove', {ssid})) aviso(`Removendo "${ssid}"…`);
  }

  $('wifiSaveOrder').addEventListener('click', () => {
    if (ordemEditada && publicar('wifi_order', {order: ordemEditada})) aviso('Gravando a nova ordem…');
  });
  $('wifiUndoOrder').addEventListener('click', () => { ordemEditada = null; aviso('Alterações desfeitas.'); renderizar(); });
  $('wifiOpen').addEventListener('change', renderizar);
  $('wifiShowPass').addEventListener('click', () => {
    const mostrar = $('wifiPass').type === 'password';
    $('wifiPass').type = mostrar ? 'text' : 'password';
    $('wifiShowPass').textContent = mostrar ? 'Ocultar' : 'Mostrar';
    $('wifiShowPass').setAttribute('aria-pressed', String(mostrar));
  });
  for (const i of [0, 1]) $('wifiDev' + i).addEventListener('click', () => {
    selecionado = i;
    ordemEditada = null;
    renderizar();
  });

  $('wifiAddForm').addEventListener('submit', async evento => {
    evento.preventDefault();
    const placa = atual();
    const ssid = $('wifiSsid').value.trim();
    const aberta = $('wifiOpen').checked;
    const senha = aberta ? '' : $('wifiPass').value;
    const bytes = t => new TextEncoder().encode(t).length;
    if (!placa) return;
    if (!ssid || bytes(ssid) > 32) { aviso('O nome da rede precisa ter de 1 a 32 caracteres.'); return; }
    if (!aberta && (bytes(senha) < 8 || bytes(senha) > 64)) { aviso('A senha Wi-Fi precisa ter de 8 a 64 caracteres.'); return; }
    if (!aberta && !placa.pubkey) { aviso('A placa ainda não publicou a chave para cifrar a senha.'); return; }
    const extras = {ssid, position: Number($('wifiPos').value), open: aberta};
    try {
      if (!aberta) Object.assign(extras, await cifrarSenha(placa.pubkey, ssid, senha));
    } catch (erro) {
      aviso('Não foi possível cifrar a senha neste navegador: ' + erro.message);
      return;
    }
    if (publicar('wifi_add', extras)) {
      aviso(`Enviando "${ssid}" (senha cifrada)…`);
      $('wifiPass').value = '';
    }
  });

  $('wifiUpdateFw').addEventListener('click', () => {
    const dev = dispositivos[selecionado];
    if (!confirm(`A placa ${dev} vai baixar o firmware publicado no GitHub e reiniciar (cerca de 1 minuto fora do ar).\n\n` +
                 'A placa de comandos recusa se houver contatores ligados.\n\nContinuar?')) return;
    if (publicar('update', {})) aviso(`Pedindo atualização de firmware para ${nomeDaPlaca().toLowerCase()}…`);
  });
  $('apOpen').addEventListener('change', renderizar);
  $('apForm').addEventListener('submit', async evento => {
    evento.preventDefault();
    const placa = atual();
    const nome = $('apName').value.trim();
    const aberta = $('apOpen').checked;
    const senha = aberta ? '' : $('apPass').value;
    const bytes = t => new TextEncoder().encode(t).length;
    if (!placa) return;
    if (!nome || bytes(nome) > 32) { aviso('O nome da rede da placa precisa ter de 1 a 32 caracteres.'); return; }
    if (!aberta && (bytes(senha) < 8 || bytes(senha) > 63)) { aviso('A senha da rede da placa precisa ter de 8 a 63 caracteres.'); return; }
    const extras = {name: nome, open: aberta};
    try {
      if (!aberta) Object.assign(extras, await cifrarSenha(placa.pubkey, nome, senha));
    } catch (erro) {
      aviso('Não foi possível cifrar a senha neste navegador: ' + erro.message);
      return;
    }
    if (publicar('wifi_ap', extras)) {
      aviso(`Enviando a rede da placa "${nome}"${aberta ? '' : ' (senha cifrada)'}…`);
      $('apPass').value = '';
    }
  });
  $('apOpenNow').addEventListener('click', () => {
    const placa = atual();
    const nome = placa?.ap?.name || 'IoTMotor-';
    if (!confirm(`A placa ${dispositivos[selecionado]} vai sair da rede atual e abrir a rede "${nome}" por 3 minutos.\n\n` +
                 'Enquanto isso ela some do painel. Conecte o celular nessa rede para cadastrar um Wi-Fi.\n\nContinuar?')) return;
    if (publicar('wifi_portal', {})) aviso(`Pedindo que ${nomeDaPlaca().toLowerCase()} abra a rede "${nome}"…`);
  });

  function conectar() {
    let cfg;
    try { cfg = lerConfiguracao(); } catch (e) { aviso(e.message); return; }
    if (!window.mqtt?.connect) { aviso('Biblioteca MQTT indisponível.'); return; }
    if (client) client.end(true);
    prefixo = cfg.p;
    dispositivos = cfg.d;
    for (const k of Object.keys(placas)) delete placas[k];
    for (const k of Object.keys(estados)) delete estados[k];
    ordemEditada = null;
    pendente = null;
    const ativo = window.mqtt.connect(cfg.url, {
      clientId: `iotmotor_wifi_${Math.random().toString(36).slice(2, 12)}`,
      clean: true, reconnectPeriod: 4000, connectTimeout: 10000, protocolVersion: 4, keepalive: 30
    });
    client = ativo;
    ativo.on('connect', () => {
      if (client !== ativo) return;
      connected = true;
      const topicos = dispositivos.flatMap(d =>
        [topico(d, 'wifi'), topico(d, 'command_ack'), topico(d, 'auth'), topico(d, 'status')]);
      ativo.subscribe(topicos, {qos: 1});
      renderizar();
    });
    ativo.on('message', (nome, payload) => {
      if (client !== ativo) return;
      const placaDoStatus = dispositivos.find(d => nome === topico(d, 'status'));
      if (placaDoStatus) {  // "online" / "offline": texto puro, não JSON.
        estados[placaDoStatus] = payload.toString('utf8').trim();
        renderizar();
        return;
      }
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      const dev = dispositivos.find(d => nome === topico(d, 'wifi') ||
        nome === topico(d, 'command_ack') || nome === topico(d, 'auth'));
      if (!dev || dados?.device_id !== dev) return;
      if (nome === topico(dev, 'auth')) {  // Desafio da placa, retido.
        window.iotmotorSelo?.registrarAuth(dev, dados);
        renderizar();
        return;
      }
      if (nome === topico(dev, 'wifi')) {
        if (!Array.isArray(dados.networks)) return;
        placas[dev] = {
          pubkey: typeof dados.pubkey === 'string' ? dados.pubkey : '',
          networks: dados.networks.filter(r => r && typeof r.ssid === 'string')
            .map(r => ({ssid: r.ssid, open: r.open === true})),
          connected: typeof dados.connected === 'string' ? dados.connected : '',
          ap: dados.ap && typeof dados.ap.name === 'string' ? {name: dados.ap.name, open: dados.ap.open === true} : null,
          max: Number(dados.max) || 8,
          em: Date.now()
        };
        if (dev === dispositivos[selecionado] && !pendente) ordemEditada = null;
      } else if (pendente && dados.seq === pendente.seq) {
        aviso((dados.accepted ? 'Placa confirmou: ' : 'Placa recusou: ') + (dados.reason || dados.action));
        if (dados.accepted) ordemEditada = null;
        pendente = null;
      }
      renderizar();
    });
    const QUEDA_TOLERADA_MS = 6000;
    let quedaTimer = null;
    const caiu = () => {
      if (client !== ativo || quedaTimer) return;
      quedaTimer = setTimeout(() => {
        quedaTimer = null;
        if (client !== ativo || ativo.connected) return;
        connected = false;
        renderizar();
      }, QUEDA_TOLERADA_MS);
    };
    const voltou = () => {
      if (quedaTimer) { clearTimeout(quedaTimer); quedaTimer = null; }
    };
    ativo.on('offline', caiu);
    ativo.on('close', caiu);
    ativo.on('reconnect', caiu);
    ativo.on('connect', voltou);
    renderizar();
  }

  function desconectar() {
    if (client) client.end(true);
    client = null;
    connected = false;
    pendente = null;
    window.iotmotorSelo?.esquecer();
    renderizar();
  }

  // Ligado ao botao Conectar/Desconectar do painel (dual-dashboard.js).
  window.iotmotorWifi = {connect: conectar, disconnect: desconectar};
  renderizar();
})();

if (typeof module !== 'undefined' && module.exports) module.exports = {cifrarSenha, ROTULO_KDF};
