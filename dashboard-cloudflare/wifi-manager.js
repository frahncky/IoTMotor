'use strict';
// Aba "Wi-Fi das placas": lista de redes gravada em cada ESP32, na ordem de
// prioridade definida aqui. Fala com as placas pelo mesmo broker MQTT.
//
// A senha NUNCA vai em texto aberto: a placa publica uma chave publica P-256
// no topico .../wifi; o navegador faz ECDH com uma chave efemera, deriva a
// chave AES-256 como SHA-256("iotmotor-wifi-v1" || segredo) e cifra a senha em
// AES-GCM usando o SSID como dado autenticado. Mesmo esquema de wifi_store.h.

const ROTULO_KDF = 'iotmotor-wifi-v1';

// Versão do firmware que está publicada para OTA (release firmware-latest,
// compilada da main junto com este painel): [quadro de comando, sensores].
// O CI confere que é a mesma do firmware_version de cada .ino.
const FIRMWARE_PUBLICADO = ['v26-mqtt-cloudflare', 's3-sensors-1.20-mqtt-cloudflare'];

const MOTIVOS_REINICIO = {
  0: 'desconhecido', 1: 'energização', 2: 'reset externo',
  3: 'reinício por software', 4: 'travamento (pânico)',
  5: 'watchdog de interrupção', 6: 'watchdog de tarefa',
  7: 'watchdog', 8: 'saída de deep sleep',
  9: 'queda de tensão (brownout)', 10: 'reinício SDIO',
  11: 'reinício USB', 12: 'reinício JTAG',
  13: 'erro de eFuse', 14: 'oscilação de alimentação',
  15: 'travamento da CPU'
};

function avaliarSaudePlaca(diagnostico, online = true) {
  if (!diagnostico) return {kind: 'unknown', texto: 'Saúde: aguardando diagnóstico da placa.'};
  if (!online) return {kind: 'offline', texto: 'Saúde: placa offline; exibindo o último diagnóstico recebido.'};

  const criticos = [], avisos = [];
  const rssi = Number(diagnostico.rssi);
  if (Number.isFinite(rssi) && rssi < 0) {
    if (rssi <= -80) criticos.push('sinal Wi-Fi muito fraco');
    else if (rssi <= -70) avisos.push('sinal Wi-Fi fraco');
  }

  const heap = Number(diagnostico.heap_bytes);
  const heapMinimo = Number(diagnostico.min_heap_bytes);
  if ((heap > 0 && heap < 65536) || (heapMinimo > 0 && heapMinimo < 40960))
    criticos.push('memória livre muito baixa');
  else if ((heap > 0 && heap < 102400) || (heapMinimo > 0 && heapMinimo < 65536))
    avisos.push('memória livre baixa');

  const reinicio = Math.max(0, Number(diagnostico.reset_reason) || 0);
  if ([4, 5, 6, 7, 9, 14, 15].includes(reinicio))
    criticos.push('último reinício: ' + (MOTIVOS_REINICIO[reinicio] || 'código ' + reinicio));

  const reconexoes = Math.max(0, Number(diagnostico.reconnections) || 0);
  const horas = Math.max(0.25, (Number(diagnostico.uptime_ms) || 0) / 3600000);
  if (reconexoes >= 3 && reconexoes / horas >= 1)
    avisos.push('reconexões Wi-Fi frequentes');

  const problemas = [...criticos, ...avisos];
  if (!problemas.length) return {kind: 'ok', texto: 'Saúde: normal.'};
  return {
    kind: criticos.length ? 'error' : 'warn',
    texto: (criticos.length ? 'Saúde: atenção crítica — ' : 'Saúde: atenção — ') + problemas.join('; ') + '.'
  };
}

// O que dizer sobre a versão que a placa informa. Exportada para os testes.
function situacaoFirmware(instalado, publicado, quadro = false) {
  if (!instalado) return {texto: 'Firmware: a placa não informou a versão (firmware antigo?).', atualizar: true};
  if (instalado === publicado) return {texto: `Firmware: ${instalado} · em dia.`, atualizar: false};
  return {texto: `Firmware: ${instalado} · nova versão publicada: ${publicado}. ` +
    `Use "Atualizar firmware desta placa"${quadro ? ' com o motor parado' : ''}.`, atualizar: true};
}

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
  let selecionado = 0, sequencia = 0;
  const pendentes = {};  // device -> {seq, dev, acao, fase, timer}
  const placas = {};  // device -> {pubkey, networks:[{ssid,open}], connected, max, em}
  // A lista de redes é retida: continua no broker depois que a placa cai. Sem
  // olhar o status, a aba dizia "conectada em ..." de uma placa desligada.
  const estados = {};  // device -> 'online' | 'offline'
  const versoes = {};  // device -> firmware_version (tópico capabilities, retido)
  const atualizados = {};  // device -> {version, em}, concluído nesta sessão do painel
  let ordemEditada = null;  // lista de SSIDs enquanto o usuario reordena

  const topico = (dev, tipo) => `${prefixo}/${dev}/${tipo}`;
  const atual = () => placas[dispositivos[selecionado]];
  const nomeDaPlaca = () => selecionado === 0 ? 'Quadro de comando' : 'Sensores do motor';
  // Mensagens gerais ficam no rodapé da seção. Mensagens de firmware ficam
  // somente junto aos botões de manutenção, para não duplicar informação.
  const aviso = texto => { $('wifiFeedback').textContent = texto; };
  const avisoFirmware = texto => {
    const el = $('wifiActionFeedback');
    if (!el) return;
    el.textContent = texto;
    el.hidden = !texto;
  };
  const pendenteDe = dev => pendentes[dev] || null;
  const limparPendente = dev => {
    const p = pendentes[dev];
    if (p?.timer) clearTimeout(p.timer);
    delete pendentes[dev];
  };
  const limparTodosPendentes = () => {
    for (const dev of Object.keys(pendentes)) limparPendente(dev);
  };

  // Estado OTA compartilhado com o painel principal. Assim os indicadores
  // "Quadro de comando" e "Sensores do motor" não continuam dizendo apenas
  // "conectado" enquanto uma atualização está em andamento.
  const OTA_CONCLUIDA_VISIVEL_MS = 30000;
  function estadoFirmwareCompartilhado(dev) {
    if (!connected) return null;
    const p = pendenteDe(dev);
    if (p?.acao === 'update') {
      return {state: 'updating', phase: p.fase, label: 'atualizando firmware'};
    }
    const concluida = atualizados[dev];
    if (concluida &&
        estados[dev] !== 'offline' &&
        Date.now() - concluida.em <= OTA_CONCLUIDA_VISIVEL_MS) {
      return {
        state: 'updated',
        phase: 'completed',
        label: 'atualizado · conectado',
        version: concluida.version
      };
    }
    return null;
  }
  window.iotmotorFirmwareStatus = estadoFirmwareCompartilhado;

  function lerConfiguracao() {
    const url = new URL(String($('broker').value || 'wss://test.mosquitto.org:8081').trim());
    const p = String($('prefix').value || 'iotmotor').trim().replace(/^\/+|\/+$/g, '');
    const d = [String($('commandDevice').value || 'esp32-01').trim(), String($('sensorDevice').value || 'esp32-02').trim()];
    if (url.protocol !== 'wss:' || url.username || url.password ||
        !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(p) || d.some(x => !/^[a-zA-Z0-9_-]+$/.test(x)))
      throw Error('Configuração MQTT inválida.');
    return {url: url.toString(), p, d};
  }

  const motivosWifi = {
    2: 'autenticação expirada', 4: 'inatividade ou sinal perdido',
    8: 'desassociação solicitada', 15: 'timeout na troca de chaves',
    201: 'rede não encontrada', 202: 'falha de autenticação',
    203: 'falha de associação', 204: 'timeout do handshake',
    205: 'falha de conexão'
  };

  function duracao(ms) {
    const segundos = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
    if (segundos < 60) return segundos + ' s';
    const minutos = Math.floor(segundos / 60);
    if (minutos < 60) return minutos + ' min ' + (segundos % 60) + ' s';
    const horas = Math.floor(minutos / 60);
    return horas + ' h ' + (minutos % 60) + ' min';
  }

  function qualidadeRssi(rssi) {
    if (rssi >= -55) return 'excelente';
    if (rssi >= -67) return 'bom';
    if (rssi >= -75) return 'fraco';
    return 'muito fraco';
  }

  function renderizarDiagnostico(placa, online) {
    const d = placa?.diagnostics;
    const saude = avaliarSaudePlaca(d, online);
    $('boardHealth').className = 'board-health ' + saude.kind;
    $('boardHealth').textContent = saude.texto;
    if (!d) {
      $('wifiRssi').textContent = $('wifiConnectedTime').textContent =
        $('wifiLastNetwork').textContent = $('wifiReconnects').textContent =
        $('wifiDisconnectReason').textContent = $('boardUptime').textContent =
        $('boardHeap').textContent = $('boardResetReason').textContent = 'não informado';
      return;
    }
    const rssi = Number(d.rssi);
    $('wifiRssi').textContent = online && Number.isFinite(rssi) && rssi < 0
      ? rssi + ' dBm · ' + qualidadeRssi(rssi) : 'sem sinal atual';
    const base = Math.max(0, Number(d.connected_ms) || 0);
    $('wifiConnectedTime').textContent = online
      ? duracao(base + Math.max(0, Date.now() - placa.em)) : 'desconectada';
    $('wifiLastNetwork').textContent = d.last_network || 'nenhuma registrada';
    $('wifiReconnects').textContent = String(Math.max(0, Number(d.reconnections) || 0));
    const razao = Math.max(0, Number(d.disconnect_reason) || 0);
    $('wifiDisconnectReason').textContent = razao
      ? (motivosWifi[razao] || 'código Wi-Fi ' + razao) + ' (' + razao + ')'
      : 'nenhuma desde o boot';
    const uptimeBase = Math.max(0, Number(d.uptime_ms) || 0);
    $('boardUptime').textContent = duracao(uptimeBase + Math.max(0, Date.now() - placa.em));
    const heap = Math.max(0, Number(d.heap_bytes) || 0);
    const heapMinimo = Math.max(0, Number(d.min_heap_bytes) || 0);
    $('boardHeap').textContent = heap && heapMinimo
      ? Math.round(heap / 1024) + ' / ' + Math.round(heapMinimo / 1024) + ' KB'
      : 'não informado';
    const reset = Math.max(0, Number(d.reset_reason) || 0);
    $('boardResetReason').textContent = MOTIVOS_REINICIO[reset] || 'código ' + reset;
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
    // Versão do firmware: a placa selecionada em detalhe, as duas no seletor e na aba.
    const firmware = dispositivos.map((d, i) => versoes[d] === undefined ? null
      : situacaoFirmware(versoes[d], FIRMWARE_PUBLICADO[i], i === 0));
    firmware.forEach((f, i) => {
      $('wifiDev' + i).dataset.update = String(Boolean(connected && f?.atualizar));
      if (connected && f?.atualizar) $('wifiDev' + i).title += ' · atualização de firmware disponível';
    });
    const algumaDesatualizada = connected && firmware.some(f => f?.atualizar);
    $('tabBtn-wifi').dataset.update = String(algumaDesatualizada);
    $('tabBtn-wifi').title = algumaDesatualizada ? 'Há atualização de firmware para uma das placas' : '';
    const minha = firmware[selecionado];
    const ota = pendenteDe(dev)?.acao === 'update' ? pendenteDe(dev) : null;
    const atualizado = atualizados[dev] || null;
    const noAr = () => estados[dispositivos[selecionado]] !== 'offline';
    renderizarDiagnostico(placa, connected && noAr());
    if (!connected) {
      $('wifiFirmware').textContent = '';
    } else if (ota) {
      $('wifiFirmware').textContent =
        ota.fase === 'enviado'
          ? 'Firmware: Atualizando firmware… aguardando confirmação da placa.'
          : ota.fase === 'reiniciando'
            ? 'Firmware: Atualizando firmware… reiniciando e reconectando.'
            : ota.fase === 'confirmando'
              ? 'Firmware: Atualizando firmware… conectado, confirmando versão.'
              : 'Firmware: Atualizando firmware… download e gravação em andamento.';
    } else if (atualizado && noAr()) {
      $('wifiFirmware').textContent = `Firmware: ${atualizado.version} · Atualizado · Conectado.`;
    } else {
      $('wifiFirmware').textContent = minha ? minha.texto
        : 'Firmware: aguardando a placa informar a versão…';
    }
    $('wifiUpdateFw').className = `btn ${connected && minha?.atualizar && !ota ? '' : 'secondary'}`.trim();
    $('wifiUpdateFw').textContent = ota ? '⭳ Atualizando firmware…' : '⭳ Atualizar firmware desta placa';
    lista.replaceChildren();

    if (!connected) $('wifiStatus').textContent = 'Conecte ao MQTT (botão no topo) para ver e editar as redes.';
    else if (ota) {
      const etapa = ota.fase === 'reiniciando'
        ? 'reiniciando e reconectando'
        : ota.fase === 'confirmando'
          ? 'conectada novamente; confirmando a nova versão'
          : ota.fase === 'enviado'
            ? 'aguardando confirmação para iniciar a atualização'
            : 'baixando e gravando o novo firmware';
      $('wifiStatus').textContent = `${nomeDaPlaca()}: Atualizando firmware… ${etapa}.`;
    } else if (atualizado && noAr()) {
      $('wifiStatus').textContent = `${nomeDaPlaca()}: Atualizado · Conectado.`;
    } else if (!placa) $('wifiStatus').textContent = `${nomeDaPlaca()} ainda não publicou a lista de redes. Se estiver online, ` +
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
    $('wifiSaveOrder').disabled = !connected || !mudou || Boolean(pendenteDe(dev)) || !noAr();
    $('wifiUndoOrder').disabled = !mudou;
    $('wifiAddBtn').disabled = !connected || !placa || Boolean(pendenteDe(dev)) || !noAr() ||
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
    const livre = connected && Boolean(placa) && !pendenteDe(dev) && noAr();
    $('apSaveBtn').disabled = !livre || (!$('apOpen').checked && !placa.pubkey);
    $('apOpenNow').disabled = !livre;
    // Atualizar firmware fica sempre clicável. O clique explica se a
    // placa está offline, em dia ou já atualizando, em vez de deixar o botão cinza.
    $('wifiUpdateFw').disabled = false;
    $('wifiRestart').disabled = !connected || Boolean(pendenteDe(dev)) || !noAr();
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
    const informar = acao === 'update' || acao === 'restart' ? avisoFirmware : aviso;
    if (!client?.connected) { informar('Sem conexão com o broker.'); return false; }
    const dev = dispositivos[selecionado];
    const impede = window.iotmotorSelo?.impedimento(dev);
    if (impede) { informar(impede); return false; }
    const seq = String(sequencia = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequencia + 1));
    const ativo = client;
    if (pendenteDe(dev)) {
      informar('Já existe uma operação em andamento nesta placa.');
      return false;
    }
    const pendente = pendentes[dev] = {seq, dev, acao, fase: 'enviado', timer: null};
    // O comando sai cifrado quando a placa exige senha (command-seal.js).
    const comando = {v: 1, device_id: dev, seq, action: acao, boot: '', mode: 'none',
      mask: 0, main: 0, star: 0, delta: 0, seconds: 0, ...extras};
    const selo = window.iotmotorSelo;
    const enviar = texto => {
      if (client === ativo && pendenteDe(dev)?.seq === seq)
        client.publish(topico(dev, 'command'), texto, {qos: 1, retain: false});
    };
    const aberto = selo ? selo.empacotarAberto(dev, comando) : JSON.stringify(comando);
    if (aberto !== null) enviar(aberto);
    else selo.empacotar(dev, comando).then(enviar).catch(erro => {
      if (client !== ativo || pendenteDe(dev)?.seq !== seq) return;
      limparPendente(dev); informar('Não deu para selar o comando: ' + (erro.message || erro)); renderizar();
    });
    pendente.timer = setTimeout(() => {
      const atualPendente = pendenteDe(dev);
      if (atualPendente?.seq !== seq || atualPendente.fase !== 'enviado') return;
      limparPendente(dev);
      if (acao === 'restart') {
        avisoFirmware(`${dev}: reinício solicitado, mas a reconexão ainda não foi confirmada.`);
      } else {
        informar(`Sem resposta de ${dev}. A placa está online?`);
      }
      renderizar();
    }, acao === 'restart' ? 30000 : 8000);
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
    avisoFirmware('');
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
    const p = pendenteDe(dev);
    const indice = dispositivos.indexOf(dev);
    const minha = indice >= 0 && versoes[dev] !== undefined
      ? situacaoFirmware(versoes[dev], FIRMWARE_PUBLICADO[indice], indice === 0)
      : null;

    if (!connected || !client?.connected) {
      avisoFirmware('Conecte ao MQTT para atualizar o firmware.');
      return;
    }
    if (p?.acao === 'update') {
      avisoFirmware(`Atualização de ${nomeDaPlaca().toLowerCase()} já está em andamento.`);
      return;
    }
    if (estados[dev] === 'offline') {
      avisoFirmware(`${nomeDaPlaca()} está offline. Aguarde a placa reconectar para atualizar.`);
      return;
    }
    if (minha && !minha.atualizar) {
      avisoFirmware(`${nomeDaPlaca()}: firmware já está atualizado (${versoes[dev]}).`);
      return;
    }

    if (!confirm(`A placa ${dev} vai baixar o firmware publicado no GitHub e reiniciar (cerca de 1 minuto fora do ar).\n\n` +
                 'A placa de comandos recusa se houver contatores ligados.\n\nContinuar?')) return;
    delete atualizados[dev];
    if (publicar('update', {})) avisoFirmware(`Pedindo atualização de firmware para ${nomeDaPlaca().toLowerCase()}…`);
  });
  $('wifiRestart').addEventListener('click', () => {
    // O quadro recusa com contatores ligados: reiniciar desliga os relés.
    const texto = selecionado === 0
      ? 'O quadro de comando vai reiniciar (alguns segundos fora do ar).\n\n' +
        'Ele recusa se houver contatores ligados: pare o motor antes.\n\nContinuar?'
      : 'A placa de sensores vai reiniciar (alguns segundos sem leituras).\n\n' +
        'O motor não é afetado: esta placa só mede.\n\nContinuar?';
    if (!confirm(texto)) return;
    if (publicar('restart', {})) avisoFirmware(`Pedindo para ${nomeDaPlaca().toLowerCase()} reiniciar…`);
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
    for (const k of Object.keys(versoes)) delete versoes[k];
    for (const k of Object.keys(atualizados)) delete atualizados[k];
    ordemEditada = null;
    limparTodosPendentes();
    const ativo = window.mqtt.connect(cfg.url, {
      clientId: `iotmotor_wifi_${Math.random().toString(36).slice(2, 12)}`,
      clean: true, reconnectPeriod: 4000, connectTimeout: 10000, protocolVersion: 4, keepalive: 30
    });
    client = ativo;
    ativo.on('connect', () => {
      if (client !== ativo) return;
      connected = true;
      const topicos = dispositivos.flatMap(d =>
        [topico(d, 'wifi'), topico(d, 'command_ack'), topico(d, 'auth'), topico(d, 'status'),
         topico(d, 'capabilities')]);
      ativo.subscribe(topicos, {qos: 1});
      renderizar();
    });
    ativo.on('message', (nome, payload) => {
      if (client !== ativo) return;
      const placaDoStatus = dispositivos.find(d => nome === topico(d, 'status'));
      if (placaDoStatus) {  // "online" / "offline": texto puro, não JSON.
        const estado = payload.toString('utf8').trim();
        estados[placaDoStatus] = estado;
        const p = pendenteDe(placaDoStatus);
        if (p?.acao === 'update' && p.fase !== 'enviado') {
          if (estado === 'offline') p.fase = 'reiniciando';
          else if (estado === 'online' && p.fase === 'reiniciando') p.fase = 'confirmando';
        } else if (p?.acao === 'restart') {
          if (estado === 'offline') {
            p.fase = 'reiniciando';
            avisoFirmware(`${placaDoStatus}: reiniciando… aguardando reconexão.`);
          } else if (estado === 'online' && p.fase === 'reiniciando') {
            limparPendente(placaDoStatus);
            avisoFirmware(`${placaDoStatus}: reiniciada e conectada.`);
          }
        }
        renderizar();
        return;
      }
      let dados;
      try { dados = JSON.parse(payload.toString('utf8')); } catch { return; }
      const dev = dispositivos.find(d => nome === topico(d, 'wifi') ||
        nome === topico(d, 'command_ack') || nome === topico(d, 'auth') || nome === topico(d, 'capabilities'));
      if (!dev || dados?.device_id !== dev) return;
      if (nome === topico(dev, 'capabilities')) {  // Retido; volta a cada conexão da placa.
        versoes[dev] = typeof dados.firmware_version === 'string' ? dados.firmware_version : '';
        const indice = dispositivos.indexOf(dev);
        const p = pendenteDe(dev);
        if (p?.acao === 'update' && indice >= 0 && versoes[dev] === FIRMWARE_PUBLICADO[indice]) {
          const instalada = versoes[dev];
          atualizados[dev] = {version: instalada, em: Date.now()};
          estados[dev] = 'online';  // capabilities novo prova que a placa voltou ao MQTT.
          limparPendente(dev);
          avisoFirmware(`Atualização de ${dev} concluída · firmware ${instalada} instalado.`);
        }
        renderizar();
        return;
      }
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
          diagnostics: dados.diagnostics && typeof dados.diagnostics === 'object'
            ? {
                rssi: Number(dados.diagnostics.rssi),
                connected_ms: Number(dados.diagnostics.connected_ms) || 0,
                last_network: typeof dados.diagnostics.last_network === 'string' ? dados.diagnostics.last_network : '',
                reconnections: Number(dados.diagnostics.reconnections) || 0,
                disconnect_reason: Number(dados.diagnostics.disconnect_reason) || 0,
                uptime_ms: Number(dados.diagnostics.uptime_ms) || 0,
                heap_bytes: Number(dados.diagnostics.heap_bytes) || 0,
                min_heap_bytes: Number(dados.diagnostics.min_heap_bytes) || 0,
                reset_reason: Number(dados.diagnostics.reset_reason) || 0
              } : null,
          em: Date.now()
        };
        if (dev === dispositivos[selecionado] && !pendenteDe(dev)) ordemEditada = null;
      } else {
        const p = pendenteDe(dev);
        if (p && dados.seq === p.seq) {
          const motivo = window.iotmotorSelo?.motivo?.(dados.reason) || dados.reason || dados.action;
          if (p.acao === 'update' && dados.accepted) {
            // "baixando firmware" é só o início da OTA. A conclusão real é a
            // placa reiniciar e publicar capabilities com a versão esperada.
            if (p.timer) clearTimeout(p.timer);
            p.fase = 'instalando';
            const seqAtual = p.seq;
            avisoFirmware(`${dev}: download confirmado. Aguardando reinício e nova versão…`);
            p.timer = setTimeout(() => {
              const atualPendente = pendenteDe(dev);
              if (atualPendente?.seq !== seqAtual || atualPendente.fase !== 'instalando') return;
              limparPendente(dev);
              avisoFirmware(`${dev}: atualização não confirmada. Verifique a versão e tente novamente.`);
              renderizar();
            }, 120000);
          } else if (p.acao === 'restart' && dados.accepted) {
            if (p.timer) clearTimeout(p.timer);
            p.fase = 'reiniciando';
            const seqAtual = p.seq;
            avisoFirmware(`${dev}: reinício confirmado. Aguardando reconexão…`);
            p.timer = setTimeout(() => {
              const atualPendente = pendenteDe(dev);
              if (atualPendente?.seq !== seqAtual || atualPendente.fase !== 'reiniciando') return;
              limparPendente(dev);
              avisoFirmware(`${dev}: reinício executado, mas a reconexão ainda não foi confirmada.`);
              renderizar();
            }, 30000);
          } else {
            const texto = (dados.accepted ? `${dev}: placa confirmou: ` : `${dev}: falha na atualização/comando: `) + motivo;
            (p.acao === 'update' || p.acao === 'restart' ? avisoFirmware : aviso)(texto);
            if (dados.accepted && dev === dispositivos[selecionado]) ordemEditada = null;
            limparPendente(dev);
          }
        }
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
    limparPendente();
    window.iotmotorSelo?.esquecer();
    renderizar();
  }

  // Ligado ao botao Conectar/Desconectar do painel (dual-dashboard.js).
  window.iotmotorWifi = {connect: conectar, disconnect: desconectar};
  setInterval(() => {
    const placa = atual();
    renderizarDiagnostico(placa, connected && estados[dispositivos[selecionado]] !== 'offline');
  }, 1000);
  renderizar();
})();

if (typeof module !== 'undefined' && module.exports) module.exports = {cifrarSenha, ROTULO_KDF, FIRMWARE_PUBLICADO, situacaoFirmware, avaliarSaudePlaca};
