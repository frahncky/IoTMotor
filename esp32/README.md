# Firmware IoTMotor

- **ESP32-01** (`iotmotor_esp32/iotmotor_esp32_comandos/`): PZEM-004T, LCD 20x4 e quatro relés (K1–K4) controlados por MQTT pelo painel Cloudflare. Detalhes em `LEIA-ME-BANCADA.md`.
- **ESP32-S3** (`iotmotor_esp32/iotmotor_esp32_s3_sensores/`, `esp32-02`): mede vibração (MPU6050) e temperatura (DS18B20); não aciona saídas.

Os comandos MQTT no broker público não têm autenticação. Não conecte motores ou contatores sem autenticação, intertravamento e proteções independentes.

## Como a placa entra na rede

Na energização, `wifistore::conectarEmOrdem` faz uma varredura e tenta as redes
gravadas **na ordem da lista**. A varredura só escolhe a ordem: uma rede que não
apareceu nela continua sendo tentada, com espera menor. Se nenhuma responder, a
placa tenta as credenciais que o próprio ESP32 guardou — as que o portal gravou
— e, funcionando, põe essa rede no topo da lista. Só depois de tudo isso a rede
própria da placa (portal) é aberta.

Antes de 23/09/2026 a varredura **descartava** as redes que não aparecessem
nela. Como a varredura logo após o boot costuma vir incompleta, as duas placas
abriam o portal com a rede certa já gravada, e era preciso reconfigurar a cada
energização.

## Esquema de partições

Os dois firmwares são compilados com **`min_spiffs`** (1,9 MB para a aplicação,
ainda com OTA). No padrão de fábrica cabia 1,31 MB e eles já ocupavam 92% e 91%;
com este esquema, caem para cerca de 61%.

```sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs   iotmotor_esp32/iotmotor_esp32_comandos
arduino-cli compile --fqbn esp32:esp32:esp32s3:PartitionScheme=min_spiffs iotmotor_esp32/iotmotor_esp32_s3_sensores
```

No Arduino IDE: *Ferramentas → Partition Scheme → Minimal SPIFFS (1.9MB APP with OTA)*.

A tabela de partições fica fora da área que o OTA regrava, então **a troca só vale
depois de uma gravação por cabo em cada placa**. Enquanto isso não for feito, o OTA
continua funcionando normalmente — mas só enquanto o binário couber em 1,31 MB.

## Comandos cifrados (desligado por padrão)

O broker `test.mosquitto.org` é aberto: qualquer pessoa que conheça o tópico
pode publicar em `iotmotor/esp32-01/command` e acionar um contator. **Hoje a
bancada funciona assim, por escolha: os comandos viajam abertos.** O que segura
a bancada são os limites do firmware (5 minutos de ensaio, queda após 15 s sem
rede) e, principalmente, as proteções elétricas — que não são substituídas por
software nenhum.

O firmware já traz o mecanismo pronto para quando essa escolha mudar: com uma
senha gravada, cada comando passa a viajar **cifrado e autenticado** com
AES-256-GCM.

- A chave de cada placa é `SHA-256("iotmotor-cmd-v1" | senha | device_id)`, então
  um comando selado para o quadro não vale para os sensores.
- O identificador da placa entra como dado autenticado: trocar o destino invalida
  o selo, e mexer em um byte qualquer também.
- Contra repetição, a placa publica um desafio aleatório em
  `iotmotor/<placa>/auth` (retido) e só aceita o comando que trouxer o desafio da
  vez. Assim que aceita um, sorteia outro — e sorteia um novo a cada reinício.
- A telemetria traz `secure: true` quando a placa exige selo.

A senha vem de `comando_local.h`, que fica **fora do Git** (como `wifi_local.h`).
Copie `comando_local.exemplo.h` nas duas pastas e use a mesma senha nas duas
placas, no painel e no aplicativo. Sem senha, a placa se comporta como antes e
aceita comando aberto — e avisa `secure: false`.

Nos firmwares publicados pelo CI, a senha vem do segredo **`IOTMOTOR_CMD_SENHA`**
do repositório (Settings → Secrets → Actions). **Esse segredo não existe hoje**,
então o firmware publicado aceita comando aberto e o build avisa isso. Criar o
segredo é o único passo para ligar a criptografia: o painel e o aplicativo
mostram o campo da senha sozinhos assim que uma placa passar a exigi-la.
Use uma senha longa, **sem aspas duplas nem barra invertida**.

Se a senha se perder, a saída é regravar as placas por cabo.

## Hora real das medições

As duas placas sincronizam o relógio por NTP assim que entram na rede
(`relogio.h`) e carimbam cada telemetria no campo **`ts`**, em segundos UTC.
Enquanto o NTP não responde o campo simplesmente não aparece: nenhuma placa
publica hora inventada.

O painel e o app usam esse carimbo no lugar da hora de chegada, e o CSV
exportado passa a trazer `measured_at` com `clock_source` (`placa` ou
`navegador`) ao lado — antes, um ensaio exportado depois saía com a hora de
quem exportou.
