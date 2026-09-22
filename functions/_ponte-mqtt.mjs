// Transporte da ponte WebSocket -> TCP usada em functions/mqtt.js.
//
// Nada daqui depende do runtime da Cloudflare: o socket entra como um par de
// Web Streams e o WebSocket como um objeto com addEventListener/send/close.
// E o que permite exercitar a logica fora do Workers, com dublês ou com um
// socket real do Node convertido por Duplex.toWeb().
//
// Arquivos com _ no inicio nao viram rota no Pages Functions.

// Subprotocolos que o MQTT.js pede no navegador. Se o cliente pedir um deles,
// a resposta 101 precisa devolver o escolhido.
export const SUBPROTOCOLOS_MQTT = ['mqtt', 'mqttv3.1', 'mqttv3.11'];

/** Escolhe o subprotocolo a devolver, ou null quando nada serve. */
export function escolherSubprotocolo(cabecalho) {
  const pedidos = String(cabecalho || '')
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);
  return pedidos.find(item => SUBPROTOCOLOS_MQTT.includes(item)) || null;
}

/**
 * Normaliza o payload de uma mensagem WebSocket em bytes.
 *
 * MQTT sobre WebSocket e sempre binario; texto so apareceria por engano de
 * cliente, e nesse caso e melhor deixar o broker recusar do que adivinhar.
 */
export function paraBytes(dados) {
  if (dados instanceof ArrayBuffer) return new Uint8Array(dados);
  if (ArrayBuffer.isView(dados)) {
    return new Uint8Array(dados.buffer, dados.byteOffset, dados.byteLength);
  }
  if (typeof dados === 'string') return new TextEncoder().encode(dados);
  return null;
}

const FECHOU_NORMAL = 1000;
const ERRO_INTERNO = 1011;

function fecharSilencioso(websocket, codigo, motivo) {
  try {
    websocket.close(codigo, motivo);
  } catch {
    // Já estava fechado; nada a fazer.
  }
}

/**
 * Liga os dois sentidos e devolve uma promessa que resolve quando o sentido
 * broker -> navegador termina.
 *
 * `socket` precisa expor `readable` e `writable` (Web Streams).
 * `websocket` precisa expor addEventListener('message'|'close'|'error'),
 * send() e close().
 */
export function ligar({ socket, websocket }) {
  const escritor = socket.writable.getWriter();

  // O handler de 'message' pode disparar enquanto uma escrita anterior ainda
  // esta pendente. Duas chamadas simultaneas a write() embaralhariam os bytes
  // e quebrariam o enquadramento do MQTT, entao as escritas viram uma fila.
  let fila = Promise.resolve();
  let encerrado = false;

  const encerrar = (codigo, motivo) => {
    if (encerrado) return;
    encerrado = true;
    fecharSilencioso(websocket, codigo, motivo);
    fila = fila
      .then(() => escritor.close())
      .catch(() => escritor.abort().catch(() => {}));
  };

  websocket.addEventListener('message', evento => {
    if (encerrado) return;
    const bytes = paraBytes(evento.data);
    if (!bytes || bytes.byteLength === 0) return;
    fila = fila
      .then(() => escritor.write(bytes))
      .catch(() => encerrar(ERRO_INTERNO, 'Falha ao escrever no broker.'));
  });

  websocket.addEventListener('close', () => encerrar(FECHOU_NORMAL, 'Cliente encerrou.'));
  websocket.addEventListener('error', () => encerrar(ERRO_INTERNO, 'Erro no WebSocket.'));

  // Sentido broker -> navegador.
  return (async () => {
    const leitor = socket.readable.getReader();
    try {
      for (;;) {
        const { value, done } = await leitor.read();
        if (done) break;
        if (!value || value.byteLength === 0) continue;
        if (encerrado) break;
        websocket.send(value);
      }
      encerrar(FECHOU_NORMAL, 'Broker encerrou a conexao.');
    } catch {
      encerrar(ERRO_INTERNO, 'Falha na leitura do broker.');
    } finally {
      try {
        leitor.releaseLock();
      } catch {
        // Fluxo já liberado.
      }
    }
  })();
}
