// Gera os WAVs do som do motor no app a partir da gravação do painel.
// Origem do áudio-base: Pixabay; veja docs/audio.md e THIRD_PARTY_NOTICES.md.
// Página registrada: https://pixabay.com/pt/sound-effects/search/electric-motor/
// Mantém o
// MESMO processamento (makeSampleParts de dashboard-cloudflare/motor-sound.js,
// executado no Chromium): partida, laço sem emenda e parada.
//
// Uso (na raiz do repositório, com o Playwright instalado):
//   node tools/gerar-audio-motor.js dashboard-cloudflare/motor-ligado.mp3 \
//        dashboard-cloudflare/motor-sound.js assets/audio
const fs=require('fs');const {chromium}=require('playwright');
(async()=>{
 const mp3=fs.readFileSync(process.argv[2]).toString('base64');
 const src=fs.readFileSync(process.argv[3],'utf8');
 const pick=(name)=>{const i=src.indexOf('function '+name);let d=0,j=src.indexOf('{',i);for(;j<src.length;j++){if(src[j]=='{')d++;else if(src[j]=='}'){d--;if(!d)break;}}return src.slice(i,j+1);};
 const consts=src.match(/const LOOP_START_S[\s\S]*?const CLICK_PEAK = [^;]+;/)[0];
 const code=consts+'\n'+pick('copyRange')+'\n'+pick('makeSampleParts');
 const b=await chromium.launch();const p=await b.newPage();
 const out=await p.evaluate(async([mp3,code])=>{
  const bytes=Uint8Array.from(atob(mp3),c=>c.charCodeAt(0));
  const ctx=new OfflineAudioContext(2,44100,44100);
  const decoded=await ctx.decodeAudioData(bytes.buffer);
  const parts=(new Function(code+'\nreturn makeSampleParts;'))()(ctx,decoded);
  const rate=decoded.sampleRate, ch=decoded.numberOfChannels;
  const GAIN=parts.level*0.57;  // Mesmo nível do painel em 100% (gainForVolume(100) = 0,57).
  const ls=Math.round(parts.loopStart*rate), le=Math.round(parts.loopEnd*rate), xf=Math.round(0.25*rate);
  const take=(buf,from,to,shape)=>{const n=to-from;const res=[];for(let c=0;c<ch;c++){const d=buf.getChannelData(c);const o=new Float32Array(n);for(let i=0;i<n;i++)o[i]=d[from+i]*GAIN*(shape?shape(i,n):1);res.push(Array.from(o));}return res;};
  // Partida: do início até 0,25 s depois do começo do laço, saindo em cosseno
  // (o laço entra em seno por cima: potência constante na troca).
  const partida=take(parts.main,0,ls+xf,(i,n)=>i<n-xf?1:Math.cos((i-(n-xf))/xf*Math.PI/2));
  const laco=take(parts.main,ls,le);   // Emenda já fundida pelo makeSampleParts.
  const parada=take(parts.outro,0,parts.outro.length);
  return {rate,ch,partida,laco,parada,loopStart:parts.loopStart,loopEnd:parts.loopEnd,level:parts.level};
 },[mp3,code]);
 const wav=(chans,rate)=>{const n=chans[0].length,ch=chans.length;const buf=Buffer.alloc(44+n*ch*2);
  buf.write('RIFF',0);buf.writeUInt32LE(36+n*ch*2,4);buf.write('WAVE',8);buf.write('fmt ',12);buf.writeUInt32LE(16,16);buf.writeUInt16LE(1,20);buf.writeUInt16LE(ch,22);buf.writeUInt32LE(rate,24);buf.writeUInt32LE(rate*ch*2,28);buf.writeUInt16LE(ch*2,32);buf.writeUInt16LE(16,34);buf.write('data',36);buf.writeUInt32LE(n*ch*2,40);
  let peak=0;for(let i=0;i<n;i++)for(let c=0;c<ch;c++){const v=Math.max(-1,Math.min(1,chans[c][i]));peak=Math.max(peak,Math.abs(v));buf.writeInt16LE(Math.round(v*32767),44+(i*ch+c)*2);}return {buf,peak};};
 for(const k of ['partida','laco','parada']){const {buf,peak}=wav(out[k],out.rate);fs.writeFileSync(process.argv[4]+'/motor-'+k+'.wav',buf);console.log(k,(out[k][0].length/out.rate).toFixed(3)+'s','pico',peak.toFixed(3),buf.length+' bytes');}
 console.log('canais',out.ch,'taxa',out.rate,'laço',out.loopStart,'→',out.loopEnd,'nível',out.level.toFixed(3));
 await b.close();})();
