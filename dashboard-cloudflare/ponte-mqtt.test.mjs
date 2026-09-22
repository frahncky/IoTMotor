import test from 'node:test';
import assert from 'node:assert/strict';

import {
  escolherSubprotocolo,
  ligar,
  paraBytes,
  SUBPROTOCOLOS_MQTT,
} from '../functions/_ponte-mqtt.mjs';

// Dublê do socket da Cloudflare: um par de Web Streams, como o connect() devolve.
function socketFalso() {
  const doBroker = new TransformStream();
  const paraOBroker = new TransformStream();
  return {
    socket: { readable: doBroker.readable, writable: paraOBroker.writable },
    // Quem "e" o broker escreve aqui e le do outro lado.
    escreverComoBroker: doBroker.writable.getWriter(),
    lerComoBroker: paraOBroker.readable.getReader(),
  };
}

// Dublê do WebSocket: mesma superfície que o Workers expõe.
function websocketFalso() {
  const ouvintes = { message: [], close: [], error: [] };
  const enviados = [];
  const fechamentos = [];
  return {
    enviados,
    fechamentos,
    disparar(tipo, evento) {
      for (const fn of ouvintes[tipo]) fn(evento);
    },
    addEventListener(tipo, fn) {
      ouvintes[tipo].push(fn);
    },
    send(dados) {
      enviados.push(Uint8Array.from(dados));
    },
    close(codigo, motivo) {
      fechamentos.push({ codigo, motivo });
    },
  };
}

const bytes = (...valores) => new Uint8Array(valores);

test('escolherSubprotocolo devolve o que o MQTT.js pede', () => {
  assert.equal(escolherSubprotocolo('mqtt'), 'mqtt');
  assert.equal(escolherSubprotocolo(' mqttv3.1 , outro '), 'mqttv3.1');
  // Preferência pela ordem do cliente, entre os que a ponte aceita.
  assert.equal(escolherSubprotocolo('desconhecido, mqtt'), 'mqtt');
});

test('escolherSubprotocolo recusa o que nao serve', () => {
  assert.equal(escolherSubprotocolo('chat'), null);
  assert.equal(escolherSubprotocolo(''), null);
  assert.equal(escolherSubprotocolo(null), null);
});

test('SUBPROTOCOLOS_MQTT cobre os nomes usados pelo MQTT.js', () => {
  assert.ok(SUBPROTOCOLOS_MQTT.includes('mqtt'));
  assert.ok(SUBPROTOCOLOS_MQTT.includes('mqttv3.1'));
});

test('paraBytes aceita ArrayBuffer, view e texto', () => {
  assert.deepEqual(paraBytes(bytes(1, 2, 3).buffer), bytes(1, 2, 3));
  assert.deepEqual(paraBytes(bytes(4, 5)), bytes(4, 5));
  assert.deepEqual(paraBytes('AB'), bytes(65, 66));
  assert.equal(paraBytes(42), null);
});

test('paraBytes respeita o recorte de uma view parcial', () => {
  // Uma view sobre parte de um buffer maior nao pode arrastar o resto junto:
  // isso corromperia o enquadramento do MQTT.
  const completo = bytes(9, 9, 1, 2, 9);
  const recorte = new Uint8Array(completo.buffer, 2, 2);
  assert.deepEqual(paraBytes(recorte), bytes(1, 2));
});

test('encaminha do navegador para o broker preservando a ordem', async () => {
  const { socket, lerComoBroker } = socketFalso();
  const websocket = websocketFalso();
  ligar({ socket, websocket });

  websocket.disparar('message', { data: bytes(0x10, 0x0c) });
  websocket.disparar('message', { data: bytes(0x82, 0x05).buffer });
  websocket.disparar('message', { data: bytes(0x30, 0x03) });

  assert.deepEqual((await lerComoBroker.read()).value, bytes(0x10, 0x0c));
  assert.deepEqual((await lerComoBroker.read()).value, bytes(0x82, 0x05));
  assert.deepEqual((await lerComoBroker.read()).value, bytes(0x30, 0x03));
});

test('encaminha do broker para o navegador', async () => {
  const { socket, escreverComoBroker } = socketFalso();
  const websocket = websocketFalso();
  const pronto = ligar({ socket, websocket });

  await escreverComoBroker.write(bytes(0x20, 0x02, 0x00, 0x00));
  await escreverComoBroker.write(bytes(0x90, 0x03));
  await escreverComoBroker.close();
  await pronto;

  assert.deepEqual(websocket.enviados, [bytes(0x20, 0x02, 0x00, 0x00), bytes(0x90, 0x03)]);
});

test('fim do broker fecha o WebSocket com codigo normal', async () => {
  const { socket, escreverComoBroker } = socketFalso();
  const websocket = websocketFalso();
  const pronto = ligar({ socket, websocket });

  await escreverComoBroker.close();
  await pronto;

  assert.equal(websocket.fechamentos.length, 1);
  assert.equal(websocket.fechamentos[0].codigo, 1000);
});

test('quadro vazio nao vira escrita nem envio', async () => {
  const { socket, escreverComoBroker } = socketFalso();
  const websocket = websocketFalso();
  const pronto = ligar({ socket, websocket });

  websocket.disparar('message', { data: new Uint8Array(0) });
  await escreverComoBroker.write(new Uint8Array(0));
  await escreverComoBroker.close();
  await pronto;

  assert.deepEqual(websocket.enviados, []);
});

test('navegador desconectando fecha uma vez so', async () => {
  const { socket } = socketFalso();
  const websocket = websocketFalso();
  ligar({ socket, websocket });

  websocket.disparar('close', {});
  websocket.disparar('close', {});

  assert.equal(websocket.fechamentos.length, 1, 'fechar duas vezes seria erro');
});

test('mensagem depois do fechamento e ignorada', async () => {
  const { socket, lerComoBroker } = socketFalso();
  const websocket = websocketFalso();
  ligar({ socket, websocket });

  websocket.disparar('close', {});
  websocket.disparar('message', { data: bytes(0x30, 0x01) });

  // Fechar encerra o escritor, entao o lado do broker ve o fim do fluxo e nunca
  // o quadro atrasado. O relogio so existe para o teste falhar em vez de travar
  // caso a ponte deixe de fechar o escritor.
  const SEM_RESPOSTA = Symbol('sem resposta');
  let relogio;
  const leitura = await Promise.race([
    lerComoBroker.read(),
    new Promise(resolve => {
      relogio = setTimeout(() => resolve(SEM_RESPOSTA), 2000);
    }),
  ]);
  clearTimeout(relogio);

  assert.notEqual(leitura, SEM_RESPOSTA, 'o escritor ficou aberto apos o fechamento');
  assert.equal(leitura.done, true, 'nao pode escrever apos o fechamento');
  assert.equal(leitura.value, undefined);
});
