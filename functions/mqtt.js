// Ponte WebSocket -> MQTT servida em https://<dominio>/mqtt.
//
// Motivo: a pagina e servida por HTTPS, e dai o navegador so aceita wss://.
// O unico WSS do test.mosquitto.org e a porta 8081, que a rede IFMA_IOT
// bloqueia — por isso o painel abria e ficava "Desconectado" la dentro,
// funcionando no 4G. Aqui o navegador fala wss:// na porta 443 com o proprio
// dominio do painel (que comprovadamente passa, pois a pagina carrega), e a
// Cloudflare abre o TCP ate o broker.
//
// Mesma solucao que o ota_update.h ja usa para a atualizacao de firmware:
// sair pela 443, que nenhuma rede institucional costuma fechar.

import { connect } from 'cloudflare:sockets';
import { escolherSubprotocolo, ligar } from './_ponte-mqtt.mjs';

// Destino FIXO, de proposito. Uma ponte que aceitasse host e porta do cliente
// seria um proxy TCP aberto no dominio de voces: qualquer um poderia alcancar
// qualquer servidor atraves da Cloudflare. E o mesmo raciocinio da URL fixa
// do ota_update.h.
const DESTINO = { hostname: 'test.mosquitto.org', port: 1883 };

function respostaDeUpgrade(cliente, request) {
  const escolhido = escolherSubprotocolo(request.headers.get('Sec-WebSocket-Protocol'));
  const headers = escolhido ? { 'Sec-WebSocket-Protocol': escolhido } : undefined;
  return new Response(null, { status: 101, webSocket: cliente, headers });
}

export async function onRequest({ request, waitUntil }) {
  if (request.method !== 'GET') {
    return new Response('Use GET com Upgrade: websocket.\n', {
      status: 405,
      headers: { Allow: 'GET', 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }

  if ((request.headers.get('Upgrade') || '').toLowerCase() !== 'websocket') {
    return new Response(
      'Esta rota e a ponte MQTT sobre WebSocket do IoTMotor.\n' +
        'Aponte o painel para wss://<este-dominio>/mqtt.\n',
      {
        status: 426,
        headers: { Upgrade: 'websocket', 'Content-Type': 'text/plain; charset=utf-8' },
      },
    );
  }

  const [cliente, servidor] = Object.values(new WebSocketPair());
  servidor.accept();

  let socket;
  try {
    socket = connect(DESTINO);
  } catch {
    // A resposta 101 ja foi prometida ao navegador; o erro vai pelo close.
    servidor.close(1011, 'Nao foi possivel abrir a conexao com o broker.');
    return respostaDeUpgrade(cliente, request);
  }

  // Uma conexao recusada pelo broker rejeita socket.opened; quem trata o erro
  // e o ligar(), pela leitura que falha. Este catch existe so para a rejeicao
  // nao ficar sem dono no log do Workers.
  socket.opened?.catch(() => {});

  // Sem await: a resposta 101 precisa sair agora, e a ponte segue viva
  // enquanto o WebSocket estiver aberto. O waitUntil segura a invocacao ate a
  // ponte terminar.
  const ponte = ligar({ socket, websocket: servidor });
  waitUntil?.(ponte);

  return respostaDeUpgrade(cliente, request);
}
