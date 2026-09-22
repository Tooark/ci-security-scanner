<div align="left">
  <img src="media/banner-ci-security-scanner.png" alt="CI Security Scanner" width="100%" />
</div>

# CI Security Scanner

Configuração de CI reutilizável para a imagem
[`security-scanner`](https://github.com/Tooark/base-images/tree/main/security-scanner)
da Tooark — **Trivy** (vulnerabilidades), **Hadolint** (lint de Dockerfile) e
**Betterleaks** (detecção de secrets) sob um único CLI `ark-tools`, produzindo
um relatório `ark-report-tools v1.2`.

Um repositório, duas portas de entrada:

- **GitLab** — templates de componente CI/CD em [`templates/`](templates/),
  utilizáveis via `include: remote:` de qualquer lugar ou publicados em um
  CI/CD Catalog.
- **GitHub** — uma composite Action definida por [`action.yml`](action.yml).

Nomes de input, defaults e precedência são os mesmos nos dois lados; só a
sintaxe muda.

Novo em pipelines? O
[guia de onboarding](https://tooark.github.io/ci-security-scanner/) percorre
cada arquivo deste repositório e o porquê de cada decisão, escrito para quem
conhece desenvolvimento de software, mas não CI. Fonte em [`docs/`](docs/).

🌍 **Idiomas:** [![USA Flag](https://flagcdn.com/w20/us.png) English](README.md) · ![Brazil Flag](https://flagcdn.com/w20/br.png) **Português (este arquivo)**

---

## Sumário

- [Início rápido](#início-rápido)
- [Templates e comandos](#templates-e-comandos)
- [Cache do banco do Trivy](#cache-do-banco-do-trivy)
- [Inputs](#inputs)
- [Como funciona a precedência](#como-funciona-a-precedência)
- [Secrets](#secrets)
- [Notas de segurança](#notas-de-segurança)
- [Sobrescrevendo o que os inputs não expõem](#sobrescrevendo-o-que-os-inputs-não-expõem)
- [Versionamento](#versionamento)
- [Publicação](#publicação)
- [Armadilhas](#armadilhas)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Desenvolvimento](#desenvolvimento)
- [Licença](#licença)

---

## Início rápido

### GitLab — remote include

Funciona no gitlab.com e em qualquer instância que alcance
`raw.githubusercontent.com`. Não precisa de catalog.

```yaml
include:
  - remote: "https://raw.githubusercontent.com/Tooark/ci-security-scanner/v1.0.0/templates/full-scan.yml"
    inputs:
      stage: test
      image: "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
      trivy_severity: "CRITICAL,HIGH"
      hadolint_failure_level: "warning"
```

### GitLab — CI/CD Catalog

Depois que o [projeto espelho](examples/gitlab-catalog-mirror/) publicar uma
versão na sua instância:

```yaml
include:
  - component: $CI_SERVER_FQDN/tooark/ci-security-scanner/full-scan@1.0.0
    inputs:
      image: "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
      trivy_severity: "CRITICAL,HIGH"
```

### GitHub Actions

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0 # Betterleaks precisa do history completo

- uses: Tooark/ci-security-scanner@v1.0.0
  with:
    command: full-scan
    image: "myapp:${{ github.sha }}"
    docker-socket: "true" # só quando a imagem foi construída neste runner
    trivy-severity: CRITICAL,HIGH
```

Exemplos completos em [`examples/`](examples/).

---

## Templates e comandos

Cada template do GitLab gera exatamente um job. No GitHub os mesmos scans são
selecionados pelo input `command` da Action única.

| Template GitLab                                        | `command` da Action | O que faz                                                       |
| ------------------------------------------------------ | ------------------- | --------------------------------------------------------------- |
| [`full-scan.yml`](templates/full-scan.yml)             | `full-scan`         | Imagem + código + secrets + lint de Dockerfile, relatório único |
| [`image-scan.yml`](templates/image-scan.yml)           | `image-scan`        | Scan de vulnerabilidades de uma imagem                          |
| [`filesystem-scan.yml`](templates/filesystem-scan.yml) | `filesystem-scan`   | Scan do código-fonte (lockfiles, pacotes de SO e de linguagem)  |
| [`config-scan.yml`](templates/config-scan.yml)         | `config-scan`       | Scan de IaC / misconfiguration                                  |
| [`repo-scan.yml`](templates/repo-scan.yml)             | `repo-scan`         | Scan de repositório; aceita URL remota                          |
| [`dockerfile-lint.yml`](templates/dockerfile-lint.yml) | `dockerfile-lint`   | Hadolint em um Dockerfile                                       |
| [`secret-scan.yml`](templates/secret-scan.yml)         | `secret-scan`       | Betterleaks no working tree e no history do git                 |

Os relatórios ficam em `scan-reports/` e sobem como artifacts. O `full-scan`
ainda grava o consolidado `full-scan-report.json`.

### Failure gates

| Ferramenta  | Falha quando                                               | Desligue com                            |
| ----------- | ---------------------------------------------------------- | --------------------------------------- |
| Trivy       | Uma severidade de `trivy_severity_fail` tem fix disponível | `trivy_exit_code: "0"`                  |
| Hadolint    | Há finding no nível `hadolint_failure_level` ou acima      | `hadolint_failure_level: "none"`        |
| Betterleaks | Qualquer secret é detectado                                | `betterleaks_fail_on_findings: "false"` |

No GitHub, `soft-fail: "true"` converte qualquer gate no output `exit-code` em
vez de falhar o step.

---

## Cache do banco do Trivy

Baixar o banco de vulnerabilidades a cada build é a parte mais lenta do scan e
o jeito mais fácil de esbarrar em rate limit de registry, então as duas
plataformas cacheiam. O `dockerfile-lint` e o `secret-scan` não usam cache — o
Hadolint e o Betterleaks nunca leem o banco.

**No GitLab** o `TRIVY_CACHE_DIR` aponta para `$CI_PROJECT_DIR/.cache/trivy` e
esse path é cacheado sob a chave fixa `ark-trivy-db`, então todas as branches
compartilham um banco só.

> Em instância self-hosted, o cache do runner fica no disco do próprio runner
> por padrão. Com vários runners, o job só acerta o cache quando cai no runner
> que o escreveu. Configurar
> [distributed caching](https://docs.gitlab.com/runner/configuration/autoscale/#distributed-runners-caching)
> (S3 ou equivalente) no `config.toml` é o que torna a taxa de acerto
> consistente.

**No GitHub** o banco fica no `RUNNER_TEMP`, que o job apaga ao terminar — então
o mount sozinho só ajudaria entre steps. O `actions/cache` é o que leva o banco
de um build para o outro, com uma entrada por dia por versão do scanner, e
fallback para o dia anterior para o Trivy atualizar um banco existente em vez
de buscar um inteiro.

O save é um step `actions/cache/save` separado, e não o post step automático,
porque o post step é pulado quando um step anterior falha — e esta action falha
por design quando um gate dispara. Sem essa separação, só os repositórios que
não encontram nada alimentariam o cache.

### Desligar ou congelar

| Objetivo             | GitLab                            | GitHub                  |
| -------------------- | --------------------------------- | ----------------------- |
| Desligar o cache     | Sobrescreva o job com `cache: []` | `trivy-cache: "false"`  |
| Reusar sem atualizar | `TRIVY_SKIP_DB_UPDATE: "true"`    | idem, como `env` do job |

Um banco cacheado ainda é atualizado quando o Trivy o considera desatualizado;
o cache economiza o download, não congela os dados. O `TRIVY_SKIP_DB_UPDATE`
congela de fato, trocando precisão do resultado por velocidade — a imagem
repassa a variável para o Trivy, que a lê nativamente.

---

## Inputs

O GitLab usa `snake_case` e o GitHub Actions usa `kebab-case`. Fora isso os
nomes e significados são idênticos.

### Presentes em todos os templates

| GitLab                 | Action                    | Default                           | Observações                                                            |
| ---------------------- | ------------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| `job_name`             | —                         | `security:<comando>`              | Mude para gerar o job mais de uma vez                                  |
| `stage`                | —                         | `test`                            | O stage precisa existir no pipeline                                    |
| `scanner_image`        | `scanner-image`           | `ghcr.io/tooark/security-scanner` |                                                                        |
| `scanner_version`      | `scanner-version`         | `1.9`                             | Sempre pinado                                                          |
| `allow_failure`        | `soft-fail`               | `false`                           | No GitLab o job vira não-bloqueante; na Action o exit code vira output |
| `rules`                | —                         | `[{when: on_success}]`            | No GitHub use o `if:` do próprio workflow                              |
| `tags`                 | —                         | `[]`                              | Seleção de runner                                                      |
| `timeout`              | —                         | `1h`                              |                                                                        |
| `reports_dir`          | `reports-dir`             | `scan-reports`                    |                                                                        |
| `artifacts_expire_in`  | `artifact-retention-days` | `7 days` / `7`                    | Retenção dos artifacts                                                 |
| `report_url`           | `report-url`              | —                                 | Webhooks, separados por vírgula                                        |
| `report_fail_on_error` | `report-fail-on-error`    | —                                 | Falha quando o upload falha                                            |
| `extra_args`           | `extra-args`              | —                                 | Flags repassadas depois do separador `--`                              |

### Alvos de scan

| GitLab        | Action        | Usado por                                                              |
| ------------- | ------------- | ---------------------------------------------------------------------- |
| `image`       | `image`       | `full-scan` (vazio pula a etapa de imagem), `image-scan` (obrigatório) |
| `scan_path`   | `path`        | `full-scan`                                                            |
| `path`        | `path`        | `filesystem-scan`, `config-scan`, `secret-scan`                        |
| `target`      | `target`      | `repo-scan`                                                            |
| `dockerfile`  | `dockerfile`  | `dockerfile-lint`                                                      |
| `dockerfiles` | `dockerfiles` | `full-scan`, separados por vírgula, relativos ao path do scan          |

No GitHub os paths são relativos ao workspace; a Action os reescreve para o
ponto de montagem dentro do container.

### Ajustes das ferramentas

`trivy_severity`, `trivy_severity_fail`, `trivy_ignore_unfixed`,
`trivy_ignore_unfixed_fail`, `trivy_exit_code`, `trivy_format`,
`trivy_scanners`, `trivy_timeout`, `trivy_server`, `trivy_ignorefile`,
`hadolint_failure_level`, `hadolint_config`, `hadolint_format`,
`betterleaks_fail_on_findings`, `betterleaks_redact`, `betterleaks_config`,
`betterleaks_baseline`, `sbom`, `sbom_format`, `scan_mode`, `skip_image`,
`skip_lint`, `skip_secrets`, `no_git`.

Cada um mapeia para a variável de ambiente correspondente documentada no
[README da imagem](https://github.com/Tooark/base-images/blob/main/security-scanner/README.pt-BR.md).
Cada template declara os que suporta, com descrição e valores aceitos, no seu
bloco `spec:inputs` — essa é a referência autoritativa.

### Inputs exclusivos do GitHub

| Input             | Default            | Observações                                                  |
| ----------------- | ------------------ | ------------------------------------------------------------ |
| `command`         | `full-scan`        | Seleciona o scan                                             |
| `docker-socket`   | `false`            | Monta `/var/run/docker.sock` para o Trivy ler imagens locais |
| `trivy-cache`     | `true`             | Cacheia o banco de vulnerabilidades em `RUNNER_TEMP`         |
| `soft-fail`       | `false`            | Retorna o exit code em vez de falhar o step                  |
| `upload-artifact` | `true`             | Sobe o `reports-dir` com `actions/upload-artifact`           |
| `artifact-name`   | `security-reports` |                                                              |

Outputs: `exit-code`, `reports-dir`, `report`.

---

## Como funciona a precedência

Todo ajuste resolve na mesma ordem nas duas plataformas:

```text
input  >  variável de CI/CD (GitLab) ou env do job (GitHub)  >  default da imagem
```

Um **input vazio nunca é repassado**. Isso é proposital: permite que o projeto
defina `TRIVY_SEVERITY` uma vez como variável global e deixe o input em branco
em todos os jobs, em vez de repetir o valor. Definir os dois faz o input vencer.

---

## Secrets

Valores de input aparecem na configuração renderizada do pipeline, então
secrets nunca vão como input. Passe como variável de CI/CD mascarada (GitLab)
ou `env` do job (GitHub) — o repasse para o container é automático:

`TRIVY_TOKEN`, `TRIVY_USERNAME`, `TRIVY_PASSWORD`, `REPORT_TOKEN`,
`REPORT_HEADERS`, `REPORT_SBOM_URL`, `REPORT_SBOM_TOKEN`.

```yaml
# GitHub
- uses: Tooark/ci-security-scanner@v1.0.0
  env:
    REPORT_TOKEN: ${{ secrets.REPORT_TOKEN }}
  with:
    report-url: https://security-hub.example.com/api/reports
```

O Betterleaks reda todos os secrets do relatório por padrão
(`betterleaks_redact: "100"`), e o log do job imprime só regra, arquivo, linha
e commit curto — nunca o conteúdo do secret.

---

## Notas de segurança

Quatro pontos valem saber antes de plugar isso num pipeline que tem
credenciais.

**`docker-socket: "true"` dá root no runner para o container.** O socket do
Docker é um plano de controle irrestrito do daemon, então qualquer coisa dentro
do container consegue subir um container privilegiado e ler o host. Vem
desligado e só é necessário para escanear uma imagem construída no mesmo job —
imagem já enviada para um registry não precisa. Em runner self-hosted
compartilhado, prefira enviar para o registry e escanear de lá.

**Relatórios podem conter os secrets que encontraram.** Duas configurações
transformam um artifact em vazamento: `betterleaks_redact: "0"` grava os
secrets detectados em claro, e incluir `secret` em `trivy_scanners` coloca os
achados do Trivy no relatório. Artifacts são baixáveis por qualquer um com
acesso de leitura ao repositório ou projeto, então mantenha a redação no
default a menos que o destino do artifact seja tão restrito quanto os secrets.

**Tags flutuantes são mutáveis por design.** Cada release move `v1` e `v1.0` à
força, então pinar qualquer uma das duas significa rodar no seu pipeline código
que você não revisou, depois do próximo release. A `v1.0.0` nunca é movida, mas
uma tag do GitHub pode em princípio ser reescrita por quem tem push; um remote
include pinado num commit SHA é a única referência totalmente imutável:

```yaml
include:
  - remote: "https://raw.githubusercontent.com/Tooark/ci-security-scanner/<commit-sha>/templates/full-scan.yml"
```

**O diretório de relatórios fica brevemente com escrita para todos nos runners
do GitHub.** A imagem faz drop para uid 1000, que não é o usuário do runner,
então o diretório é aberto durante o scan e fechado depois. Em runner efêmero
isso é irrelevante; em self-hosted com jobs concorrentes, outro job poderia
escrever ali durante o scan.

### O que foi verificado

Há `eval` nos templates e no `src/run-scanner.sh`, mas ele só itera uma lista
fixa de nomes de variável — nenhum input chega nele. O word splitting do
`extra_args` é proposital e roda sob `set -f`, então um valor como `*` não
expande contra os arquivos do repositório. Expressões de workflow chegam aos
blocos `run:` via `env:`, não por interpolação de string. O
`scripts/validate-templates.py` usa `yaml.safe_load`. Os tokens dos workflows
são escopados: `contents: read` no CI, `contents: write` só no job de release.
A imagem de terceiro do `actionlint` está pinada por digest, e o Dependabot
acompanha o resto.

---

## Sobrescrevendo o que os inputs não expõem

Um job gerado no GitLab é um job comum. Redeclare pelo nome para mudar o que os
inputs não cobrem:

```yaml
"security:full-scan":
  needs: ["build"]
  services:
    - docker:27-dind
  cache: [] # desliga o cache do banco do Trivy
  variables:
    TRIVY_SCANNERS: "vuln,secret,misconfig,license"
```

Para rodar o mesmo scan duas vezes com configurações diferentes, inclua o
template duas vezes com `job_name` diferente — veja
[`examples/gitlab/remote-include.gitlab-ci.yml`](examples/gitlab/remote-include.gitlab-ci.yml).

---

## Versionamento

Os releases são taggeados como `vMAJOR.MINOR.PATCH`. Cada release também move
duas tags flutuantes, para acompanhar uma linha sem editar pipeline a cada
patch:

| Referência | Resolve para                   | Use quando                            |
| ---------- | ------------------------------ | ------------------------------------- |
| `v1.0.0`   | Exatamente aquele release      | Pipeline reproduzível                 |
| `v1.0`     | Patch mais novo da 1.0         | Atualização automática de patch       |
| `v1`       | Release mais novo da linha 1.x | Atualização automática de minor/patch |
| `main`     | Trabalho não publicado         | Nunca em pipeline que importa         |

O [`VERSION`](VERSION) é a fonte única de verdade tanto da versão do componente
quanto da tag da imagem que todos os templates e a Action pinam. O
`scripts/check-sync.sh` quebra o CI se algum deles divergir, e o workflow de
release recusa uma tag que não bata com `COMPONENT_VERSION`.

Subir a versão da imagem é, portanto, uma mudança de três linhas: edite o
`VERSION`, rode `./scripts/check-sync.sh` e atualize os pins que ele apontar.

---

## Publicação

### GitHub Releases

Faça push de uma tag `v*.*.*`. O
[`.github/workflows/release.yml`](.github/workflows/release.yml) valida os
templates, confere a tag contra o `VERSION`, cria o release com notas geradas e
move as tags flutuantes.

### GitHub Marketplace

Listar no Marketplace é um opt-in manual que a API não consegue fazer: abra o
release no GitHub e marque **Publish this Action to the GitHub Marketplace**.
Só na primeira vez; os releases seguintes oferecem a mesma caixa.

### GitLab CI/CD Catalog

O catalog só lista componentes hospedados na própria instância GitLab, então um
repositório do GitHub não pode ser publicado nele diretamente. Monte o projeto
espelho descrito em
[`examples/gitlab-catalog-mirror/`](examples/gitlab-catalog-mirror/): ele
consulta os releases do GitHub por schedule, copia o `templates/` quando a
versão muda e publica no catalog interno.

---

## Armadilhas

**O override de entrypoint no GitLab é obrigatório.** O entrypoint da imagem
executa o `ark-tools` diretamente, e o GitLab Runner mantém o entrypoint da
imagem e anexa um shell a ele. Todos os templates definem `entrypoint: [""]`;
remover isso quebra o job antes do script rodar.

**`GIT_DEPTH: "0"` importa para o scan de secrets.** O Betterleaks percorre o
history do git. Com o clone raso padrão do GitLab, ou com o `fetch-depth: 1`
padrão do GitHub, ele silenciosamente quase não vê nada. Os templates definem
`git_depth: "0"`; no GitHub use `fetch-depth: 0` no `actions/checkout`.

**Escanear imagem construída no mesmo job do GitHub exige o socket.** O Trivy
procura a imagem no daemon local, que o container não alcança sem
`docker-socket: "true"`. Imagens já enviadas para um registry não precisam.

**Propriedade dos arquivos nos runners do GitHub.** A imagem faz drop para o
usuário não-root `app` (uid 1000), que não é o usuário do runner. A Action cria
o diretório de relatórios com escrita para todos e devolve a propriedade
depois, além de declarar o workspace como safe directory do git. Valores
customizados de `reports-dir` herdam esse tratamento.

**O dockerfile-lint trata um arquivo por job.** Use `full-scan` com
`dockerfiles: "a,b,c"`, ou inclua o `dockerfile-lint` uma vez por arquivo com
`job_name` diferente.

---

## Estrutura do repositório

```text
templates/          Templates de componente CI/CD do GitLab, um job cada
action.yml          Composite Action do GitHub
src/run-scanner.sh  Runner compartilhado por trás da Action
scripts/            Validações rodadas no CI e localmente
examples/           Pipelines prontos para copiar, nas duas plataformas
docs/               Guia de onboarding, publicado no GitHub Pages
VERSION             Fonte única de verdade das versões
```

---

## Desenvolvimento

```bash
python3 -m pip install pyyaml

python3 scripts/validate-templates.py   # estrutura, wiring de inputs, inputs mortos
./scripts/check-sync.sh                 # pinning de versão e paridade entre plataformas
shellcheck -s bash src/run-scanner.sh scripts/check-sync.sh
```

O CI roda os três, mais o `actionlint`, mais um self-scan em que a Action deste
repositório escaneia este repositório.

Ao adicionar um input, mexa nos quatro lugares ou o `check-sync.sh` vai avisar:
o `spec:inputs` do template, o bloco `variables:` do template como `ARK_IN_*`,
o `action.yml` e o `src/run-scanner.sh`.

---

## Licença

MIT — veja [LICENSE](LICENSE).
