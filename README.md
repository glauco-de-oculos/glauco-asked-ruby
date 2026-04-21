# GLAUCO RUBY

swt com react like state managment framework for build html desktop applications in ruby

just require_relative 'core/framework/glauco-framework'

Consult sample.rb for usage example

## Rodando com Ollama

O projeto agora usa, por padrao:

- `OLLAMA_HOST=http://127.0.0.1:11434`
- `OLLAMA_MODEL=gemma4:e4b`

O default do projeto agora e `gemma4:e4b`, o proximo tamanho acima do `e2b`:
https://ollama.com/library/gemma4

### Preparacao

```bash
cd /home/usuario/dev/glauco-asked-ruby
RBENV_VERSION=jruby-10.0.4.0 bundle install
ollama pull gemma4:e4b
```

### Subir o app

```bash
cd /home/usuario/dev/glauco-asked-ruby
./bin/floating-chat-ollama
```

### Trocar host ou modelo

```bash
OLLAMA_HOST=http://192.168.0.10:11434 OLLAMA_MODEL=gemma4:e4b ./bin/floating-chat-ollama
```

## Custos locais do framework

Foi documentada uma medicao local de custo do framework, frontend e instancia do modelo em [docs/framework-costs.md](/home/usuario/dev/glauco-asked-ruby/docs/framework-costs.md).

## Lisp/JVM direction

Foi adicionado um estudo inicial para migracao da ideia da plataforma para um dialeto Lisp na JVM:

- arquitetura sugerida em [`docs/glauco-lisp-jvm.md`](/c:/dev/glauco/docs/glauco-lisp-jvm.md)
- bootstrap minimo em [`glauco-clj/README.md`](/c:/dev/glauco/glauco-clj/README.md)

cheers!

## Build reutilizavel para projetos consumidores

Se um projeto depender de `glauco-framework`, ele pode expor um build estilo `npm run build` chamando o empacotador do gem.

Gemfile minimo no projeto consumidor:

```ruby
source "https://rubygems.org"

ruby file: ".ruby-version"

gem "glauco-framework", path: "../glauco"
gem "warbler"
```

`.ruby-version` do projeto consumidor:

```text
jruby-10.0.4.0
```

Exemplo de `package.json` no projeto consumidor:

```json
{
  "scripts": {
    "build": "bundle exec glauco-package build --entry bin/main.rb --app-name meu-app --output dist --image ghcr.io/minha-org/meu-app:latest --namespace apps"
  }
}
```

Esse comando gera no projeto consumidor:

- `dist/meu-app.jar`
- `dist/Dockerfile`
- `dist/kubernetes.yaml`

Depois disso, o fluxo de container fica:

```bash
docker build -f dist/Dockerfile -t ghcr.io/minha-org/meu-app:latest dist
kubectl apply -f dist/kubernetes.yaml
```

O `jar` e o `Dockerfile` sao gerados a partir do ambiente Ruby do proprio projeto consumidor. Em outras palavras:

- o projeto consumidor define a versao de JRuby;
- o projeto consumidor declara `warbler` no `Gemfile`;
- o container final embala a aplicacao inteira como sandbox de execucao.
