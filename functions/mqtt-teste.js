// Diagnóstico da ponte: abre o socket até o broker pelo lado da Cloudflare,
// manda um CONNECT de MQTT e conta o que voltou.
//
// Serve para separar dois problemas que parecem o mesmo no navegador: "a
// Cloudflare não chega no broker" e "a ponte não repassa os bytes". Abra
// https://iotmotor.pages.dev/mqtt-teste no navegador.
import {connect} from 'cloudflare:sockets';

const BROKER = {hostname: 'test.mosquitto.org', port: 1883};

/// CONNECT do MQTT 3.1.1, sessão limpa, keepalive de 60 s.
function pacoteConnect(clientId) {
  const nome = new TextEncoder().encode('MQTT');
  const id = new TextEncoder().encode(clientId);
  const corpo = [
    0x00, nome.length, ...nome,
    0x04,        // versão 3.1.1
    0x02,        // clean session
    0x00, 0x3c,  // keepalive 60 s
    (id.length >> 8) & 0xff, id.length & 0xff, ...id,
  ];
  const restante = [];
  let n = corpo.length;
  do {
    let byte = n % 128;
    n = Math.floor(n / 128);
    if (n > 0) byte |= 0x80;
    restante.push(byte);
  } while (n > 0);
  return new Uint8Array([0x10, ...restante, ...corpo]);
}

export async function onRequest() {
  const linhas = [];
  const inicio = Date.now();
  let tcp;
  try {
    tcp = connect(BROKER);
    linhas.push(`socket aberto para ${BROKER.hostname}:${BROKER.port}`);
  } catch (erro) {
    return texto([`FALHOU ao abrir o socket: ${erro}`]);
  }

  try {
    const escritor = tcp.writable.getWriter();
    await escritor.write(pacoteConnect('ponte-teste'));
    linhas.push('CONNECT enviado');
    escritor.releaseLock();

    const leitor = tcp.readable.getReader();
    const resposta = await Promise.race([
      leitor.read(),
      new Promise(resolve =>
        setTimeout(() => resolve({value: null, done: false}), 8000)
      ),
    ]);

    if (!resposta.value) {
      linhas.push('sem resposta em 8 s: a Cloudflare não está falando com o broker');
    } else {
      const bytes = [...resposta.value];
      const hex = bytes.map(b => b.toString(16).padStart(2, '0')).join(' ');
      linhas.push(`recebeu ${bytes.length} bytes: ${hex}`);
      if (bytes[0] === 0x20 && bytes[3] === 0x00) {
        linhas.push('CONNACK aceito: a ponte alcança o broker');
      } else if (bytes[0] === 0x20) {
        linhas.push(`CONNACK recusado, código ${bytes[3]}`);
      } else {
        linhas.push('resposta não é um CONNACK');
      }
    }
    try { tcp.close(); } catch { /* já fechado */ }
  } catch (erro) {
    linhas.push(`FALHOU durante a conversa: ${erro}`);
  }

  linhas.push(`${Date.now() - inicio} ms no total`);
  return texto(linhas);
}

function texto(linhas) {
  return new Response(linhas.join('\n') + '\n', {
    headers: {'Content-Type': 'text/plain; charset=utf-8'},
  });
}
