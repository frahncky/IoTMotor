# Guia de uso

Como operar a bancada pelo painel web e pelo app. Para os detalhes técnicos de
cada mensagem, veja a [referência MQTT](mqtt.md).

## Sumário

- [Abrir e conectar](#abrir-e-conectar)
- [A tela Painel](#a-tela-painel)
- [Dar partida no motor](#dar-partida-no-motor)
- [Somente medição (modo instrumentação)](#somente-medição-modo-instrumentação)
- [Dados do motor e manutenção](#dados-do-motor-e-manutenção)
- [Alarmes](#alarmes)
- [Histórico](#histórico)
- [Placas: Wi-Fi, atualização e reinício](#placas-wi-fi-atualização-e-reinício)
- [Senha de comando](#senha-de-comando)
- [App Android](#app-android)
  - [Alertas no celular](#alertas-no-celular)
- [Problemas comuns](#problemas-comuns)

## Abrir e conectar

1. Abra [iotmotor.pages.dev](https://iotmotor.pages.dev), no computador ou no celular.
2. Toque em **Conectar**, no topo.
3. Os selos **Quadro de comando** e **Sensores do motor** ficam verdes ("conectado") quando cada placa está mandando dados.

O endereço do broker, o prefixo e o ID de cada placa ficam em
**Configurações › Conexão MQTT**. O padrão serve para a bancada do IFMA. O
endereço `wss://iotmotor.pages.dev/mqtt` passa pela porta 443 e funciona mesmo
na rede da escola.

| Selo | Significado |
| --- | --- |
| verde · conectado | Dados chegando agora |
| âmbar · online, aguardando dados | A placa está na rede, mas ainda não mandou telemetria |
| vermelho · desconectado | A placa caiu ou está sem dados há mais de 6 s |

## A tela Painel

![Painel com o motor ligado](images/painel.png)

- **Quadro de comando:** escolha da partida, os botões **Ligar**, **Desligar** e **Somente medição**, e o estado de CNT 1 a CNT 4.
- **Diagnóstico:** o desenho do motor e, abaixo dele, as medições principais:
  - corrente e **carga em %**, quando a corrente nominal está cadastrada;
  - vibração com a classificação **ISO 10816**, quando a rotação está cadastrada;
  - temperatura;
  - uma linha de uso: *Ligado há…*, horímetro e partidas de hoje.
- **Alarmes ativos:** o que está disparado agora, sensores sem leitura, grandezas perto do limite e manutenção vencida ou próxima.
- **Grandezas elétricas e mecânicas** e **Gráficos em tempo real:** todas as medições, atualizadas a cada segundo.
- **Histórico da placa:** os últimos 7 dias, hora a hora (veja [Histórico](#histórico)).

A vibração é classificada em **Boa, Aceitável, Alerta ou Crítica**. A velocidade
em mm/s é estimada a partir da aceleração e da rotação, e as faixas dependem da
potência do motor. É uma estimativa: serve para acompanhar tendência, não
substitui um analisador de vibração.

## Dar partida no motor

1. No quadro **Quadro de comando**, escolha a partida (por exemplo, *Estrela-triângulo*).
2. Toque em **Ligar**. O título do card mostra **Ligando…** até a placa confirmar.
3. Para parar, toque em **Desligar todos**. Esse botão funciona **sempre**, mesmo durante uma partida em andamento.

As partidas ficam gravadas no quadro de comando, até 6. São as mesmas no painel e
no app. Para criar ou mudar uma, use **Nova partida** ou **Editar**:

![Editor de partida](images/guia-partida.png)

- Marque os contatores usados.
- **Liga (s):** quando o contator liga, contado a partir do Ligar.
- **Desliga (s):** quando ele desliga. `0` = fica ligado até parar.
- O nome cabe em 24 bytes. Cada acento conta 2, e o LCD mostra o nome sem acento.

O exemplo acima é a estrela-triângulo:
- CNT 1 (principal) e CNT 2 (estrela) ligam juntos;
- a estrela desliga em 5 s;
- o triângulo (CNT 3) liga 0,7 s depois.

### Segurança do ensaio

![Segurança do ensaio](images/guia-seguranca.png)

Em **Configurações › Segurança do ensaio**:
- **Duração máxima do ensaio:** padrão 5 min; pode ir de 10 s a 2 h, ou sem limite.
- **Se a conexão cair, o ensaio segue por:** padrão 15 s; de 0 (cai na hora) a 1 h, ou sem limite.

Os dois valores ficam gravados no quadro. Com a rede fora, ninguém consegue
mandar parar pelo painel: a parada tem de ser elétrica.

## Somente medição (modo instrumentação)

Serve para medir um motor acionado por outro comando elétrico, sem o ESP32 no
caminho.

- **Somente medição** faz o quadro deixar de acionar contatores: ele só mede e mostra os dados. Se houver saída ligada, ela cai na hora.
- O botão vira **Liberar acionamento** para voltar ao normal.
- O modo fica gravado na placa e sobrevive a reinício.
- Nesse modo, o horímetro e as partidas contam o motor como ligado quando a corrente passa de 0,3 A.
- Com o motor girando assim, o painel e o app mostram o motor ligado (animação, som, carga e vibração ISO), e o LED e o buzzer da placa de sensores alarmam como numa partida pelo quadro. **Ligar/Desligar** não age sobre esse motor.

## Dados do motor e manutenção

![Dados do motor](images/dados-do-motor.png)

Em **Configurações › Dados do motor**, copie a placa de identificação do motor.
Os campos ficam gravados no quadro de comando e valem para o painel e o app.
Todos são opcionais e aceitam vírgula ou ponto.

| Campo | Para que serve |
| --- | --- |
| Corrente nominal (A) | Calcular a **carga em %** |
| Tensão nominal (V) | Referência da ligação em uso |
| Tipo | Trifásico ou monofásico |
| Ligação em uso | Aparece com duas tensões: **Triângulo** ou **Estrela** |
| Potência (cv) | Escolher a faixa da ISO 10816 |
| Rotação (rpm) | Converter a vibração para mm/s |
| Fator de serviço | Referência de sobrecarga |
| Manutenção a cada (h de uso) | Lembrete de manutenção pelo horímetro |

**Motor de dupla tensão.** A placa do motor traz, por exemplo, *220/380 V —
12,6/7,3 A*. Informe exatamente assim:
- corrente `12,6/7,3`, tensão `220/380`;
- **Tipo** Trifásico;
- a **ligação em que o motor trabalha**. Na partida estrela-triângulo, ele trabalha em **triângulo**.

A carga em % usa a corrente dessa ligação.

**Manutenção.**
- Com o intervalo cadastrado, o painel mostra "Próxima manutenção em … h de uso".
- Quando faltam menos de 10% do intervalo, o aviso aparece em **Alarmes ativos**; depois do prazo, vira "Manutenção vencida".
- Depois do serviço, toque em **Manutenção feita**: a placa grava o horímetro e a data, e a contagem recomeça.

**Zerar horímetro e partidas** serve para a troca de motor. O quadro só aceita
com o motor parado, e zera também a contagem da manutenção.

## Alarmes

![Configuração de alarmes](images/guia-alarmes.png)

Os alarmes ficam gravados na **placa de sensores**, até 8. Ela avisa com o LED e
o buzzer mesmo com o painel fechado e sem internet.

- **Alarme ligado:** interruptor geral. Desligado, o buzzer não toca.
- **Bipes de eventos:** bipes curtos quando a placa conecta ou recebe comandos.
- **Tom do buzzer:** ajuste até o buzzer soar mais forte e toque em **Salvar**. **Bipar** testa o tom na hora.
- **Testar LED** e **Testar LED e buzzer** conferem a sinalização.
- **Alarmes gravados na placa:** cada linha tem a grandeza, o limite, se está ligado, **✓** para gravar a mudança e **✕** para remover.
- **Adicionar alarme:** escolha a grandeza, **acima** ou **abaixo**, e o limite.

As grandezas disponíveis são:

| Placa | Grandezas |
| --- | --- |
| Sensores do motor | vibração (pico e RMS), temperatura |
| Quadro de comando | tensão, corrente, potência, frequência, fator de potência, partidas na última hora |

As grandezas do quadro também disparam o LED e o buzzer da placa de sensores,
porque ela ouve o quadro pelo broker.

Na primeira vez, a placa vem com dois alarmes: vibração (pico) acima de 0,5 g e
temperatura acima de 60 °C.

O que o LED indica está em [Hardware › O que o LED indica](hardware.md#o-que-o-led-indica).

## Histórico

![Histórico de 7 dias](images/historico.png)

**Histórico da placa · últimos 7 dias** mostra as médias e os máximos de cada
hora, guardados na placa de sensores. O registro continua com o painel fechado.

- Escolha **Corrente, Temperatura, Vibração RMS, Tensão** ou **Tempo ligado**.
- Linha cheia = média da hora; tracejada = máximo da hora.
- Corrente e vibração só contam com o motor girando.
- A hora em andamento entra no gráfico quando termina.

Há também o **histórico do navegador**: as leituras da **última hora** recebidas
enquanto o painel está aberto, guardadas só naquele navegador. Use **Período**
(última hora, 15 min ou 5 min) e **Exportar CSV** para levar os dados para uma
planilha, e **Limpar** para apagá-los. Para períodos maiores, use o histórico da
placa acima (7 dias, por hora).

A placa de sensores continua gravando o histórico mesmo sem rede (temperatura
e vibração medidas por ela; corrente e tempo ligado dependem do quadro), e
publica os dias guardados quando volta a se conectar.

## Placas: Wi-Fi, atualização e reinício

![Aba Dispositivos](images/guia-dispositivos.png)

Na aba **Dispositivos**, escolha a placa no alto (**Quadro de comando** ou
**Sensores do motor**).

**Versão do firmware.** A linha "Firmware:" mostra a versão instalada.
- Quando há versão nova, aparece um **ponto âmbar** na aba e no nome da placa, e o botão **Atualizar firmware desta placa** fica em destaque.
- Ao atualizar, a placa baixa o firmware novo e reinicia, em cerca de 1 minuto. O painel acompanha até ela voltar com a versão nova e avisa "Atualização concluída".
- O quadro de comando só atualiza com o **motor parado**.

**Reiniciar placa** funciona como o botão de reset. O quadro recusa com
contatores ligados.

**Redes Wi-Fi.** A placa tenta as redes na ordem da lista.
- **↑ ↓** mudam a ordem; depois, toque em **Salvar ordem**.
- **Adicionar rede** grava uma rede nova. A senha vai cifrada, só a placa consegue ler.
- **✕** remove uma rede.

**Rede própria da placa.** Se a placa não achar nenhuma rede conhecida, ela abre
a própria rede (`IoTMotor-esp32-01` ou `IoTMotor-esp32-02`) por 3 minutos.
1. Conecte o celular nessa rede.
2. Cadastre o Wi-Fi na página que abrir.

**Abrir rede da placa agora** força isso, por exemplo para levar a bancada a
outro lugar.

## Senha de comando

Se as placas foram gravadas com senha ([como ligar](firmware.md#senha-de-comando)),
o campo **Senha de comando** aparece em **Configurações › Conexão MQTT**, no
painel e no app. Digite a mesma senha: sem ela, as placas recusam todos os
comandos, **menos Desligar**, que vale sempre (parar é o lado seguro). A senha
fica só naquele navegador ou celular.

## App Android

Instale pelo [APK](https://github.com/frahncky/IoTMotor/releases/download/app-latest/IoTMotor.apk).
As próximas versões chegam por **Configurações › Atualizar este app**: o app
baixa o APK e o Android pede a confirmação.

| Aba | O que tem |
| --- | --- |
| **Início** | Partida e Ligar/Desligar, cartão do motor (animação, carga, vibração ISO, horímetro, manutenção, aviso de firmware) e gráficos |
| **Histórico** | Histórico da placa (7 dias) e leituras recebidas pelo app, com exportação |
| **Alertas** | Alertas de limite e de manutenção vencida; **Reconhecer** marca como visto |
| **Configurações** | Conexão, dados do motor (**Editar dados do motor**, **Manutenção feita**), Wi-Fi, **Atualizar firmware** e **Atualizar este app** |

**Conexão no app.** O app já vem em `ws://test.mosquitto.org`, porta **8080**,
com TLS desligado: é o mesmo caminho das placas e passa em rede que bloqueia
MQTT. Cada celular usa um *client id* próprio; dois aparelhos com o mesmo id se
derrubam no broker.
**Testar caminhos de conexão** mostra qual endereço passa na rede em que você
está.

| Endereço | Porta | Quando usar |
| --- | --- | --- |
| `test.mosquitto.org` | 1883 | Rede que deixa passar MQTT |
| `ws://test.mosquitto.org` | 8080 | Rede que bloqueia as portas MQTT (IFMA) |
| `wss://test.mosquitto.org` | 8081 | WebSocket com TLS, onde a 8081 não é bloqueada |

### Alertas no celular

Em **Configurações › Alertas no celular** (desligado por padrão), o app avisa
quando um alarme da placa dispara, **mesmo fechado**.

- Os alarmes são os da lista gravada na placa de sensores: os mesmos que acendem o LED e tocam o buzzer ([Alarmes](#alarmes)). Com o monitoramento da placa desligado, o celular também fica quieto.
- Ao disparar, chega uma notificação com som, dizendo o limite e a leitura: "Alarme: Temperatura acima de 60 °C · agora 65,3 °C". Ao voltar ao normal, a mesma notificação muda para "Normalizado", sem som.
- Um alarme que oscila no limite toca no máximo uma vez a cada 5 minutos.
- Enquanto os alertas estão ligados, o Android mostra uma notificação fixa ("IoTMotor: alertas ligados"): é a exigência do sistema para o app seguir vigiando fechado. Ela diz se está conectado ao broker.
- Os alertas voltam sozinhos depois de reiniciar o celular ou atualizar o app. Usam a conexão da tela de conexão, com um *client id* próprio (`…_alertas`).
- Ao ligar, o Android pede permissão para notificações. Se o aparelho economizar bateria de forma agressiva, deixe o IoTMotor **sem restrição de bateria** para ele não ser encerrado.
- Só no Android.

## Problemas comuns

| O que aparece | O que fazer |
| --- | --- |
| "Placa recusou: esta função precisa do firmware novo" | A placa está com firmware antigo. Atualize na aba **Dispositivos** |
| Ponto âmbar na aba **Dispositivos** | Há firmware novo para uma das placas |
| Temperatura "sem leitura" | Confira o DS18B20 e o resistor de 4,7 kΩ. Se o sensor foi religado com a placa ligada, use **Reiniciar placa** nos sensores |
| O painel não conecta na escola | Confira em **Conexão MQTT** se o endereço é `wss://iotmotor.pages.dev/mqtt` |
| Uma placa aparece "desconectado" | Ela caiu da rede. Espere a reconexão ou verifique a energia; sem rede conhecida, ela abre a própria rede |
| **Ligar** recusado | Veja o motivo na mensagem: modo instrumentação ligado, saída já ligada, partida em andamento ou placa reiniciada (tente de novo) |
| Histórico da placa vazio | A placa de sensores precisa do firmware com histórico e da hora da internet. A primeira hora aparece quando termina |
| Carga em % não aparece | Cadastre a corrente nominal em **Dados do motor**. A carga só aparece com o motor ligado |
| Vibração sem classificação ISO | Cadastre a rotação (rpm). A classificação só aparece com o motor ligado |
