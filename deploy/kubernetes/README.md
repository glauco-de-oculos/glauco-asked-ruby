# Jar + Container pipeline

Este fluxo gera dois artefatos para o app principal do repo:

- `dist/glauco-app.jar`
- imagem OCI `ghcr.io/<org>/glauco/glauco-app`

## Build local do jar

```powershell
pwsh -File pipeline/scripts/package_glauco_app.ps1 `
  -ScriptPath bin/main.rb `
  -AppName glauco-app `
  -OutputDir dist `
  -SkipJlink `
  -SkipJpackage
```

## Build local da imagem

```powershell
docker build -f deploy/kubernetes/Dockerfile -t ghcr.io/seu-org/glauco/glauco-app:local .
```

## Deploy no Kubernetes

Antes de aplicar:

1. troque `ghcr.io/YOUR_ORG/glauco/glauco-app:latest` pela imagem real;
2. ajuste `OLLAMA_HOST` e `OLLAMA_MODEL`;
3. confirme se faz sentido rodar uma app SWT em container no seu ambiente.

Aplicacao:

```powershell
kubectl apply -f deploy/kubernetes/glauco-app.yaml
```

## Limite importante

O app principal ainda usa SWT e UI desktop. A pipeline abaixo gera `jar` e container, mas a viabilidade operacional em Kubernetes depende de como voces pretendem executar essa interface. Para uso pleno em cluster, o caminho mais seguro ainda e separar a parte headless do runtime desktop.
