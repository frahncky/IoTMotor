'use strict';
// Sela os comandos com a senha combinada com as placas (AES-256-GCM).
//
// O broker continua público, mas o comando viaja cifrado e autenticado: quem
// não tem a senha não consegue montar um comando que a placa aceite, nem ler o
// que foi comandado. A chave de cada placa sai de
// SHA-256("iotmotor-cmd-v1" | senha | device_id) — a mesma conta que o firmware
// faz em comando_seguro.h.
//
// Contra repetição, a placa publica um desafio em <prefixo>/<placa>/auth e só
// aceita o comando que trouxer o desafio da vez; depois de aceitar, sorteia
// outro. A senha fica só neste navegador, nunca no repositório nem no broker.
(() => {
  const ROTULO = 'iotmotor-cmd-v1';
  const GUARDA = 'iotmotor_cmd_senha';
  const texto = new TextEncoder();
  const chaves = new Map();   // placa -> CryptoKey
  const desafios = new Map(); // placa -> {secure, challenge}
  let senha = '';

  try { senha = localStorage.getItem(GUARDA) || ''; } catch { senha = ''; }

  function definirSenha(nova) {
    senha = String(nova ?? '');
    chaves.clear();
    try {
      if (senha) localStorage.setItem(GUARDA, senha);
      else localStorage.removeItem(GUARDA);
    } catch { /* navegador sem armazenamento: vale só nesta aba */ }
  }

  async function chaveDe(placa) {
    const guardada = chaves.get(placa);
    if (guardada) return guardada;
    const bruto = await crypto.subtle.digest('SHA-256', texto.encode(ROTULO + senha + placa));
    const chave = await crypto.subtle.importKey('raw', bruto, 'AES-GCM', false, ['encrypt']);
    chaves.set(placa, chave);
    return chave;
  }

  // Tópico retido da placa: diz se ela exige selo e qual é o desafio da vez.
  function registrarAuth(placa, dados) {
    if (!dados || dados.device_id !== placa) return;
    desafios.set(placa, {
      secure: dados.secure === true,
      challenge: typeof dados.challenge === 'string' ? dados.challenge : ''
    });
  }

  function esquecer(placa) {
    if (placa) desafios.delete(placa);
    else desafios.clear();
  }

  const exigeSelo = placa => desafios.get(placa)?.secure === true;
  const temSenha = () => Boolean(senha);

  // Por que um comando não sairia agora — vazio quando está tudo pronto.
  function impedimento(placa) {
    if (!exigeSelo(placa)) return '';
    if (!senha) return 'Informe a senha de comando em "Conexão MQTT" para comandar esta placa.';
    if (!desafios.get(placa).challenge) return 'Aguardando o desafio da placa.';
    if (!globalThis.crypto?.subtle) return 'Este navegador não oferece criptografia (use HTTPS).';
    return '';
  }

  // Quando a placa não exige selo, o comando sai na hora, sem promessa; quem
  // chama usa isto para não adiar um envio que não precisa de criptografia.
  function empacotarAberto(placa, comando) {
    return exigeSelo(placa) ? null : JSON.stringify(comando);
  }

  // Texto a publicar: selado quando a placa exige, aberto quando ela não exige.
  async function empacotar(placa, comando) {
    if (!exigeSelo(placa)) return JSON.stringify(comando);
    const impede = impedimento(placa);
    if (impede) throw Error(impede);
    const desafio = desafios.get(placa).challenge;
    const chave = await chaveDe(placa);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const cifrado = new Uint8Array(await crypto.subtle.encrypt(
      {name: 'AES-GCM', iv, additionalData: texto.encode(placa), tagLength: 128},
      chave,
      texto.encode(JSON.stringify({...comando, ch: desafio}))
    ));
    const junto = new Uint8Array(iv.length + cifrado.length);
    junto.set(iv);
    junto.set(cifrado, iv.length);
    let bruto = '';
    for (const byte of junto) bruto += String.fromCharCode(byte);
    return JSON.stringify({v: 1, device_id: placa, sealed: btoa(bruto)});
  }

  window.iotmotorSelo = {
    definirSenha, senhaAtual: () => senha, temSenha,
    registrarAuth, esquecer, exigeSelo, impedimento, empacotarAberto, empacotar
  };
})();
