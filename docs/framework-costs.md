# Framework Costs

Medicao local feita em `2026-04-17` no fluxo do `GlaucoBasicPlasticAgent` com `GlaucoAgentBrowserEnv` e backend local de modelo.

## Escopo da medicao

Esta medicao foi feita com o modelo `gemma-4-e2b-it`, que era o default naquele momento.

O default atual do projeto foi promovido depois para um modelo acima:

- Ollama: `gemma4:e4b`
- llama-server / GGUF: `gemma-4-e4b-it`

Entao os numeros abaixo servem como baseline historica do `e2b`, nao como custo atualizado do default atual `e4b`.

## Custo do framework

O fluxo medido parte da instancia do `GlaucoBasicPlasticAgent`, que hoje absorve o runtime antes exposto separadamente como `RLM`. No boot observado pelo frontend, a sequencia registrada foi:

```text
[Glauco] 🚀 Inicializando Glauco Framework (RLM core)...
[GlaucoAgentBrowserEnv] BEFORE bootstrap_agent!
[LLM] 🚀 bootstrap_agent! (framework bootstrap)
[GlaucoAgentBrowserEnv] AFTER bootstrap_agent!
```

Na pratica, essa instancia:

- sobe o backend de modelo quando `GLAUCO_LLM_PROVIDER=llama-server`
- sincroniza o GGUF local do framework quando necessario
- inicializa o chat e o runtime usados pelo ambiente de browser

Configuracao medida:

- Provider: `GLAUCO_LLM_PROVIDER=llama-server`
- Modelo ativo: `gemma-4-e2b-it`
- Arquivo carregado: [core/framework/models/gemma-4-e2b-it.gguf](/home/usuario/dev/glauco-asked-ruby/core/framework/models/gemma-4-e2b-it.gguf)
- Endpoint de modelo: `http://127.0.0.1:1234/v1`

## Custo do frontend

Tambem foi medida a subida do demo [examples/terminal dev app.rb](/home/usuario/dev/glauco-asked-ruby/examples/terminal%20dev%20app.rb), que instancia `GlaucoAgentBrowserEnv` e abre o browser embutido.

Comando usado:

```bash
timeout 8s /usr/bin/time -f 'elapsed=%E\nmaxrss=%MKB' \
  bash -lc 'GLAUCO_LLM_PROVIDER=llama-server jruby examples/terminal\ dev\ app.rb'
```

Resultado observado:

- O processo inicializou, exibiu o banner interativo e encerrou normalmente quando recebeu EOF
- Tempo ate o prompt: `3.34 s`
- Pico de memoria do processo JRuby/SWT: `632996 KB` (`~618 MB`)

Warnings nao fatais observados no boot:

- `Gtk-CRITICAL: gtk_clipboard_get_for_display: assertion 'display != NULL' failed`
- `custom-elements.json NOT FOUND` em `core/framework/web/node_modules/@carbon/web-components/custom-elements.json`

Esses avisos nao impediram a inicializacao do frontend nessa medicao. O ponto importante e que, depois da inicializacao lazy do `Frontend`, o demo passou a subir ate o prompt sem abortar o processo.

## Custo da instancia do modelo

O processo ativo foi confirmado com:

```bash
ps -eo pid,ppid,%cpu,%mem,rss,etime,command | rg 'llama-server --model'
curl -s http://127.0.0.1:1234/v1/models
```

Resultado observado:

- Processo: `llama-server --model /home/usuario/dev/glauco-asked-ruby/core/framework/models/gemma-4-e2b-it.gguf --host 127.0.0.1 --port 1234 --alias gemma-4-e2b-it`
- Alias exposto pelo servidor: `gemma-4-e2b-it`
- Tamanho do GGUF local: `2.9 GB`
- Parametros reportados pelo servidor: `4,647,450,147`
- Contexto de treino reportado: `131072`

Medicao de uma chamada direta ao endpoint `/v1/chat/completions`:

```bash
curl -s -o /tmp/glauco_llama_bench.json -w 'total=%{time_total}\nconnect=%{time_connect}\nstarttransfer=%{time_starttransfer}\nhttp=%{http_code}\nsize=%{size_download}\n' \
  http://127.0.0.1:1234/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"gemma-4-e2b-it","messages":[{"role":"system","content":"You are concise."},{"role":"user","content":"Reply with exactly one short sentence saying hi in Portuguese."}],"temperature":0,"max_tokens":24}'
```

Numeros capturados:

- Tempo total: `1.519545 s`
- Tempo ate primeiro byte: `1.519463 s`
- HTTP status: `200`
- Prompt tokens: `31`
- Completion tokens: `24`
- Total tokens: `55`
- Prompt throughput: `106.89 tok/s`
- Generation throughput: `19.86 tok/s`

Uso do processo durante a medicao:

- PID: `44398`
- CPU observada: `2.9%`
- Memoria residente: `5,139,032 KB` (`~4.9 GB`)
- Memoria virtual: `7,068,780 KB`

Nao ha custo por token de API externa, porque a inferencia esta sendo feita localmente.

Custos locais observados:

- RAM da instancia do modelo: `~4.9 GB`
- Disco do modelo no framework: `2.9 GB`
- CPU em repouso observada apos carga: `~2.9%`

## Observacao funcional

Nesta configuracao, a resposta de teste retornou `reasoning_content` e encerrou com `finish_reason=length`, entao parte do orcamento de tokens foi consumida pelo raciocinio do modelo em vez da resposta final. Isso significa que o backend esta operacional, mas ainda pode precisar de ajuste de prompt ou parametros para uso interativo mais eficiente.
