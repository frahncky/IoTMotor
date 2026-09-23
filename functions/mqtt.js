// Ponte do painel até o broker, servida pela própria Cloudflare.
//
// O painel precisa de wss://, e a rede do IFMA bloqueia a porta 8081 do broker
// público — em alguns computadores, em alguns dias. Aqui o navegador abre a
// conexão no mesmo endereço do painel (porta 443, a do HTTPS, que nenhuma rede
// bloqueia sem derrubar a internet inteira) e a Cloudflare, que está fora do
// firewall da escola, fala com o broker.
//
// Do lado do broker a ponte usa MQTT sobre TCP (1883). Os quadros que trafegam
// no WebSocket são exatamente os mesmos bytes do MQTT sobre TCP, então o
// repasse é byte a byte, sem interpretar nada.
//
// O trecho navegador -> Cloudflare é cifrado (wss). O trecho Cloudflare ->
// broker vai em claro, como já vai o das placas.
import {connect} from 'cloudflare:sockets';

const BROKER = {hostname: 'test.mosquitto.org', port: 1883};

export async function onRequest(context) {
  if (context.request.headers.get('Upgrade') !== 'websocket') {
    return new Response(
      'Este endereço é a ponte MQTT do painel: abra-o como WebSocket ' +
        '(wss://.../mqtt), não pelo navegador.',
      {status: 426, headers: {'Content-Type': 'text/plain; charset=utf-8'}}
    );
  }

  // Com ?debug=1 a ponte narra o que faz, em frames de texto. Um cliente MQTT
  // de verdade nunca usa isso: serve para descobrir onde os bytes param.
  const contando = new URL(context.request.url).searchParams.get('debug') === '1';

  const par = new WebSocketPair();
  const paraONavegador = par[0];
  const daPonte = par[1];
  daPonte.accept();

  const responder = () =>
    new Response(null, {
      status: 101,
      webSocket: paraONavegador,
      headers: {'Sec-WebSocket-Protocol': 'mqtt'}
    });

  // Fechar dizendo o motivo: sem isso, uma falha aqui vira "não conecta" e
  // ninguém descobre por quê.
  let encerrada = false;
  const encerrar = motivo => {
    if (encerrada) return;
    encerrada = true;
    try { daPonte.close(1011, String(motivo).slice(0, 120)); } catch { /* já fechado */ }
  };

  let tcp;
  try {
    tcp = connect(BROKER);
    // Esperar a abertura de fato: escrever antes disso falha em silêncio.
    await tcp.opened;
  } catch (erro) {
    encerrar(`broker inacessível: ${erro}`);
    return responder();
  }

  const narrar = texto => {
    if (!contando) return;
    try { daPonte.send(`[ponte] ${texto}`); } catch { /* já fechado */ }
  };
  narrar('socket TCP aberto com o broker');

  const escritor = tcp.writable.getWriter();
  // Uma fila só: o MQTT depende da ordem dos bytes.
  let fila = Promise.resolve();
  daPonte.addEventListener('message', evento => {
    const dados = evento.data;
    const bytes =
      typeof dados === 'string'
        ? new TextEncoder().encode(dados)
        : new Uint8Array(dados);
    narrar(`recebi ${bytes.length} bytes do navegador`);
    fila = fila
      .then(() => escritor.write(bytes))
      .then(() => narrar('repassei ao broker'))
      .catch(erro => encerrar(`falha ao enviar ao broker: ${erro}`));
  });
  for (const evento of ['close', 'error']) {
    daPonte.addEventListener(evento, () => {
      encerrada = true;
      try { tcp.close(); } catch { /* já fechado */ }
    });
  }

  // Do broker para o navegador, enquanto houver bytes.
  context.waitUntil(
    (async () => {
      const leitor = tcp.readable.getReader();
      try {
        for (;;) {
          const {value, done} = await leitor.read();
          if (done) break;
          narrar(`${value.length} bytes do broker`);
          daPonte.send(value);
        }
        encerrar('broker encerrou a conexão');
      } catch (erro) {
        encerrar(`broker caiu: ${erro}`);
      }
    })()
  );

  narrar('ponte pronta');
  return responder();
}
