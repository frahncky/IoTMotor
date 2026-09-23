// Ponte WebSocket do painel até o broker, servida pela própria Cloudflare.
//
// O painel precisa de wss://, e a rede do IFMA bloqueia a porta 8081 do
// broker público — em alguns computadores, em alguns dias. Aqui o navegador
// abre a conexão no mesmo endereço do painel (porta 443, a do HTTPS, que
// nenhuma rede bloqueia sem derrubar a internet inteira) e a Cloudflare, que
// está fora do firewall da escola, repassa tudo para o broker.
//
// Nada é interpretado no caminho: os quadros MQTT passam intactos nos dois
// sentidos. O broker continua sendo o mesmo das placas.
// A Cloudflare so faz requisicao de saida em um conjunto de portas, e a 8081
// do broker nao esta nele -- a 8080 esta, e e a mesma que as placas usam. O
// trecho navegador -> Cloudflare continua cifrado (wss, porta 443); o trecho
// Cloudflare -> broker vai em claro, como ja vai o das placas.
const BROKER = 'http://test.mosquitto.org:8080/';

export async function onRequest(context) {
  const pedido = context.request;
  if (pedido.headers.get('Upgrade') !== 'websocket') {
    return new Response(
      'Este endereço é a ponte MQTT do painel: abra-o como WebSocket ' +
        '(wss://.../mqtt), não pelo navegador.',
      {status: 426, headers: {'Content-Type': 'text/plain; charset=utf-8'}}
    );
  }

  let resposta;
  try {
    resposta = await fetch(BROKER, {
      headers: {
        Upgrade: 'websocket',
        Connection: 'Upgrade',
        // mqtt.js pede este subprotocolo; o broker recusa a conexão sem ele.
        'Sec-WebSocket-Protocol': 'mqtt'
      }
    });
  } catch (erro) {
    return new Response(`Broker fora do ar: ${erro}`, {status: 502});
  }

  const doBroker = resposta.webSocket;
  if (!doBroker) {
    return new Response(
      `O broker não aceitou a conexão (HTTP ${resposta.status}).`,
      {status: 502}
    );
  }

  const par = new WebSocketPair();
  const paraONavegador = par[0];
  const daPonte = par[1];

  doBroker.accept();
  daPonte.accept();

  // Repasse nos dois sentidos, sem olhar o conteúdo.
  daPonte.addEventListener('message', evento => {
    try { doBroker.send(evento.data); } catch { /* já fechado */ }
  });
  doBroker.addEventListener('message', evento => {
    try { daPonte.send(evento.data); } catch { /* já fechado */ }
  });

  // Fechar de um lado fecha o outro, para não deixar conexão pendurada.
  const encerrar = (origem, destino) => {
    for (const evento of ['close', 'error']) {
      origem.addEventListener(evento, e => {
        try { destino.close(e.code && e.code >= 1000 ? e.code : 1011, e.reason || ''); }
        catch { /* já fechado */ }
      });
    }
  };
  encerrar(daPonte, doBroker);
  encerrar(doBroker, daPonte);

  return new Response(null, {
    status: 101,
    webSocket: paraONavegador,
    headers: {'Sec-WebSocket-Protocol': 'mqtt'}
  });
}
