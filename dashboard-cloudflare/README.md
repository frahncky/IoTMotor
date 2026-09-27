# Painel web

Página estática publicada pelo Cloudflare Pages em
[iotmotor.pages.dev](https://iotmotor.pages.dev). Não tem build: HTML e
JavaScript puros, falando MQTT com as placas pelo broker.

- Como usar: [docs/guia-de-uso.md](../docs/guia-de-uso.md)
- Tópicos e comandos: [docs/mqtt.md](../docs/mqtt.md)
- Módulos, testes, publicação, ponte na porta 443 e Cloudflare Access: [docs/desenvolvimento.md](../docs/desenvolvimento.md)

Testes:

```sh
node --test dashboard-cloudflare/*.test.cjs
```
