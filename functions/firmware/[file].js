const RELEASE_BASE = 'https://github.com/frahncky/IoTMotor/releases/download/firmware-latest/';

// Binarios do OTA e, para o painel e o app, a versao publicada (gravada pelo
// publish-firmware.yml). O navegador nao le o release do GitHub direto (CORS).
const TIPOS = {
  'esp32-01.bin': 'application/octet-stream',
  'esp32-02.bin': 'application/octet-stream',
  'firmware-latest.json': 'application/json; charset=utf-8'
};

export async function onRequestGet(context) {
  const arquivo = String(context.params.file || '');
  if (!Object.hasOwn(TIPOS, arquivo)) {
    return new Response('Firmware nao encontrado', {status: 404});
  }

  const origem = RELEASE_BASE + arquivo;
  const resposta = await fetch(origem, {
    redirect: 'follow',
    headers: {'User-Agent': 'IoTMotor-OTA-Proxy'}
  });

  if (!resposta.ok || !resposta.body) {
    return new Response('Falha ao obter firmware publicado', {status: 502});
  }

  const headers = new Headers();
  headers.set('Content-Type', TIPOS[arquivo]);
  const tamanho = resposta.headers.get('Content-Length');
  if (tamanho) headers.set('Content-Length', tamanho);
  headers.set('Cache-Control', 'no-store');
  headers.set('X-IoTMotor-Source', 'firmware-latest');

  return new Response(resposta.body, {
    status: 200,
    headers
  });
}
