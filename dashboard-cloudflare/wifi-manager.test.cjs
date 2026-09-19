const test = require('node:test');
const assert = require('node:assert/strict');
const {webcrypto: cripto} = require('node:crypto');
const {cifrarSenha, ROTULO_KDF} = require('./wifi-manager.js');

// Faz o papel da placa: mesmo esquema de wifi_store.h (ECDH P-256,
// SHA-256(rotulo || segredo), AES-GCM com o SSID como dado autenticado).
async function decifrarComoAPlaca(chavePrivada, ssid, {epk, iv, ct}) {
  const sutil = cripto.subtle;
  const b64 = t => Uint8Array.from(Buffer.from(t, 'base64'));
  const efemera = await sutil.importKey('raw', b64(epk), {name: 'ECDH', namedCurve: 'P-256'}, false, []);
  const segredo = new Uint8Array(await sutil.deriveBits({name: 'ECDH', public: efemera}, chavePrivada, 256));
  const material = Buffer.concat([Buffer.from(ROTULO_KDF), Buffer.from(segredo)]);
  const chave = await sutil.importKey('raw', await sutil.digest('SHA-256', material), 'AES-GCM', false, ['decrypt']);
  const claro = await sutil.decrypt({name: 'AES-GCM', iv: b64(iv), additionalData: Buffer.from(ssid)}, chave, b64(ct));
  return Buffer.from(claro).toString('utf8');
}

async function parDaPlaca() {
  const par = await cripto.subtle.generateKey({name: 'ECDH', namedCurve: 'P-256'}, true, ['deriveBits']);
  const publica = Buffer.from(await cripto.subtle.exportKey('raw', par.publicKey)).toString('base64');
  return {privada: par.privateKey, publica};
}

test('a placa recupera a senha cifrada pelo painel', async () => {
  const placa = await parDaPlaca();
  const pacote = await cifrarSenha(placa.publica, 'Francisco S20 fe', 'senha secreta çã', cripto);
  assert.equal(Buffer.from(pacote.epk, 'base64').length, 65, 'chave efemera P-256 nao comprimida');
  assert.equal(Buffer.from(pacote.iv, 'base64').length, 12);
  assert.equal(await decifrarComoAPlaca(placa.privada, 'Francisco S20 fe', pacote), 'senha secreta çã');
});

test('o texto cifrado nao contem a senha e muda a cada envio', async () => {
  const placa = await parDaPlaca();
  const a = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  const b = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  assert.ok(!JSON.stringify(a).includes('minhasenha123'));
  assert.notEqual(a.ct, b.ct);
});

test('trocar o SSID invalida o pacote (SSID e dado autenticado)', async () => {
  const placa = await parDaPlaca();
  const pacote = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  await assert.rejects(decifrarComoAPlaca(placa.privada, 'Outra rede', pacote));
});

test('outra placa nao consegue decifrar', async () => {
  const placa = await parDaPlaca();
  const intrusa = await parDaPlaca();
  const pacote = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  await assert.rejects(decifrarComoAPlaca(intrusa.privada, 'Casa', pacote));
});
