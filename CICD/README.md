# Plantilla CI/CD: CodeCommit → mirror a Git remoto → Terraform multi-cuenta

Plantilla Terraform **reutilizable** para levantar, de cero, un flujo completo de CI/CD:

- El código fuente vive en **AWS CodeCommit** (creado por esta misma plantilla).
- Cada push dispara un pipeline que primero **espeja el repo a un remoto Git externo**
  (GitHub, GitLab, o cualquier otro — ver sección "Git remoto").
- Después ejecuta **Terraform** (`plan` / `apply`) contra una cuenta AWS destino distinta por entorno.
- Rama `develop` → despliegue **automático** (plan + apply sin intervención).
- Rama `main` (o `master`) → plan automático + **aprobación manual obligatoria** antes de aplicar.
- Todos los nombres de recursos desplegados llevan **prefijo/sufijo de entorno** (`dev`, `main`) para poder convivir en cuentas separadas o en la misma cuenta sin colisionar.
- **La cuenta AWS destino de cada entorno se gestiona desde un único punto** (SSM Parameter Store), sin tener que volver a aplicar todo el Terraform del pipeline para rotarla.
- **El mirror hacia el remoto Git es agnóstico al proveedor.** La creación del repo remoto (si no existe) es un script independiente y sustituible por proveedor.

Pensada para copiarse a un nuevo proyecto y arrancar cambiando solo variables/parámetros, no código.

---

## 1. Arquitectura

```
                                   ┌─────────────────────────────┐
                                   │   Developer / CI local      │
                                   │   git push origin develop   │
                                   │   git push origin main      │
                                   └──────────────┬───────────────┘
                                                  │
                                                  ▼
                                   ┌─────────────────────────────┐
                                   │      AWS CodeCommit         │
                                   │  (repo creado por Terraform)│
                                   │   ramas: develop / main     │
                                   └──────────────┬───────────────┘
                                                  │ EventBridge rule
                                                  │ (referenceCreated/Updated
                                                  │  filtrado por rama)
                        ┌─────────────────────────┴─────────────────────────┐
                        ▼                                                   ▼
        ┌───────────────────────────────┐                 ┌───────────────────────────────┐
        │  CodePipeline "develop"       │                 │  CodePipeline "main"          │
        │                               │                 │                               │
        │ 1. Source (CodeCommit)        │                 │ 1. Source (CodeCommit)        │
        │ 2. CodeBuild: mirror-git      │                 │ 2. CodeBuild: mirror-git      │
        │ 3. CodeBuild: terraform-plan  │                 │ 3. CodeBuild: terraform-plan  │
        │ 4. CodeBuild: terraform-apply │                 │ 4. Manual Approval  ⚠️        │
        │    (AUTO, sin aprobación)     │                 │ 5. CodeBuild: terraform-apply │
        └───────────────┬───────────────┘                 └───────────────┬───────────────┘
                        │ sts:AssumeRole                                   │ sts:AssumeRole
                        │ (ARN leído de SSM en runtime)                    │ (ARN leído de SSM en runtime)
                        ▼                                                   ▼
        ┌───────────────────────────────┐                 ┌───────────────────────────────┐
        │   Cuenta AWS "dev"            │                 │   Cuenta AWS "main/prod"      │
        │   role: cicd-deploy-role      │                 │   role: cicd-deploy-role      │
        │   recursos con prefijo "dev-" │                 │   recursos con prefijo "main-"│
        └───────────────────────────────┘                 └───────────────────────────────┘

        Paso "mirror-git-remote" (stage 2, en ambos pipelines) — 100% AGNÓSTICO:
          - Hace fetch del repo CodeCommit (source stage ya lo clona)
          - git push --mirror hacia GIT_REMOTE_HOST/GIT_REMOTE_PATH, autenticado con un
            token desde Secrets Manager (Basic Auth genérica, no específica de proveedor)
          - Si el remoto no existe, el push falla y el mensaje de error indica qué script
            de creación ejecutar — el pipeline NUNCA llama a ninguna API REST de plataforma

        Configuración "de un único punto" (fuera de este Terraform):
          - scripts/set-cross-account-target.sh    -> escribe en SSM el rol a asumir por entorno
          - scripts/create-remote-repo-github.sh    -> crea el repo en GitHub si no existe
          - scripts/create-remote-repo-gitlab.sh    -> crea el proyecto en GitLab si no existe
          - (añade el equivalente para tu proveedor: Bitbucket, Azure DevOps, etc.)
```

### Por qué así (decisiones y alternativas descartadas)

- **CodeCommit sí admite repos nuevos** en esta cuenta (verificado empíricamente creando y borrando un repo de prueba). La documentación pública indica que está cerrado a *nuevos clientes* de AWS, pero cuentas existentes conservan la capacidad de crear repos — no es una prohibición universal.
- **No existe mirroring nativo servidor-a-servidor de CodeCommit hacia repos externos.** La única forma soportada por AWS es la técnica de cliente (`git remote set-url --add --push`), que requiere que *alguien* ejecute el push. Por eso el mirror se implementa como el primer stage de CodeBuild del propio pipeline: se dispara solo con cada push a CodeCommit, sin componentes adicionales (nada de Lambda + EventBridge extra).
- **CodeDeploy no participa.** CodeDeploy despliega *aplicaciones* a cómputo existente (EC2/ECS/Lambda vía `appspec.yml`), no ejecuta Terraform. El despliegue de infraestructura corre en CodeBuild.
- **El mirror (`buildspecs/mirror.yml`) es agnóstico al proveedor Git; la creación del repo NO lo es, y es intencional.** `git push`/`fetch`/`clone` son protocolo Git puro — funcionan igual contra GitHub, GitLab, Bitbucket o cualquier servidor Git, con solo host+path+token. Pero **crear** un repositorio nuevo no forma parte del protocolo Git: cada plataforma lo resuelve con su propia API REST/GraphQL (gestión de organizaciones, permisos, cuotas...). Por eso la plantilla separa:
  - `buildspecs/mirror.yml`: solo `git push --mirror`, sin ninguna llamada a ninguna API de plataforma. Cambiar de GitHub a GitLab (o a cualquier otro proveedor con soporte Git estándar) no requiere tocar este archivo, solo los valores de `git_remote_host`/`git_remote_path`.
  - `scripts/create-remote-repo-<proveedor>.sh`: script aparte, específico de cada plataforma, ejecutado manualmente una vez antes del primer push. Añadir soporte para un proveedor nuevo es solo escribir un script más, sin tocar Terraform ni el pipeline.
  - Se descartó gestionar la creación del repo con el provider Terraform de GitLab (`gitlab_project`) porque acopla el ciclo de vida de la plataforma Git con el de la infraestructura AWS del pipeline, y el atributo `mirror` de ese provider tiene bugs conocidos y abiertos para mirroring continuo (`gitlab-org/terraform-provider-gitlab#6317`).
- **La cuenta AWS destino de cada entorno vive en SSM, no en `terraform.tfvars`.** El Terraform del pipeline (`pipeline/`) **lee** (`data "aws_ssm_parameter"`) el ARN del rol cross-account, pero no lo escribe. Rotar de cuenta, apuntar temporalmente a otra, o dar de alta un rol nuevo se hace con un único comando (`scripts/set-cross-account-target.sh`) sin tocar código Terraform. La policy IAM de CodeBuild sí necesita conocer el ARN en tiempo de "apply" del pipeline (para poder autorizar el `sts:AssumeRole`), así que tras cambiar el parámetro en SSM hay que reaplicar `pipeline/` una vez para resincronizar esa policy — esto es intencional: la policy nunca es más permisiva que "los ARNs conocidos en el último apply", en vez de un wildcard abierto.
- **Dos pipelines (uno por rama) en vez de uno parametrizado.** La acción `Manual Approval` de CodePipeline es declarativa: no hay forma limpia de hacerla condicional dentro de un único pipeline. Con dos pipelines, cada stage-list mapea 1:1 a su rama.
- **No existe un servicio nativo de AWS que "clone" este tipo de plantilla con un clic** salvo Service Catalog o Proton, que añaden una capa de abstracción innecesaria para este caso. Terraform puro parametrizado (módulo raíz + `tfvars` por instancia) es el patrón estándar para plantillas reutilizables y es lo que se usa aquí.

---

## 2. Estructura de carpetas

```
CICD/
├── README.md                        # este documento
├── bootstrap/                        # Fase 0: crea el bucket S3 + tabla DynamoDB del backend remoto
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── scripts/
│   ├── create-remote-repo-github.sh # crea el repo en GitHub si no existe (paso manual, una vez)
│   ├── create-remote-repo-gitlab.sh # idem para GitLab
│   └── set-cross-account-target.sh  # único punto para definir/rotar la cuenta destino por entorno
│
├── pipeline/                        # Terraform: CodeCommit, pipelines, CodeBuild, IAM, Secrets/SSM propios
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── backend.tf
│   ├── providers.tf
│   ├── codecommit.tf
│   ├── secrets.tf
│   ├── iam.tf
│   ├── codebuild.tf
│   ├── pipelines.tf
│   └── outputs.tf
│
├── iam-cross-account/                # Terraform a aplicar EN CADA CUENTA DESTINO (dev, main/prod...)
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── modules/
│   └── app-infra/                    # módulo de ejemplo (dummy) parametrizado por entorno
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   └── terraform.tfvars.example
│   └── main/
│       ├── backend.tf
│       ├── main.tf
│       └── terraform.tfvars.example
│
└── buildspecs/
    ├── mirror.yml   # 100% agnóstico al proveedor Git
    ├── plan.yml
    └── apply.yml
```

---

## 3. Orden de despliegue (bootstrap)

Esta plantilla separa deliberadamente "infraestructura del pipeline" (Terraform) de "configuración
operativa que cambia con frecuencia" (scripts + SSM). El bootstrap es en 5 fases:

1. **Fase 0 — Backend de estado.** Aplicar `bootstrap/` (con state LOCAL, ya que este módulo es
   quien crea el backend remoto que usará el resto de la plantilla):
   ```bash
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # y edita project_name
   terraform init
   terraform apply
   ```
   Esto crea el bucket S3 + tabla DynamoDB para el `backend` remoto de Terraform (el de
   `pipeline/` y el de cada `environments/*`). Se aplica una única vez por proyecto.
2. **Fase 1 — Rol cross-account en cada cuenta destino.** Aplicar `iam-cross-account/` **en la
   cuenta de dev** y, cuando exista, **en la cuenta de main/prod**, usando credenciales de
   administrador de esa cuenta (una sola vez por cuenta). Esto crea el rol que CodeBuild podrá
   asumir. Anota el `role_arn` que devuelve como output.
3. **Fase 2 — Publicar el rol cross-account en SSM.** Por cada entorno, ejecutar:
   ```bash
   ./scripts/set-cross-account-target.sh \
     --project mi-proyecto --environment dev \
     --role-arn <role_arn de la Fase 1> --profile mi-perfil-aws
   ```
   Este paso **debe completarse antes** del primer `terraform apply` de `pipeline/`, porque
   `pipeline/secrets.tf` lee ese parámetro como `data source` (si no existe, el apply falla).
4. **Fase 3 — Pipeline.** Aplicar `pipeline/` en la cuenta donde vive el CI/CD. Esto crea
   CodeCommit, los CodeBuild, y los dos CodePipeline.
5. **Fase 4 — Repo remoto + primer push.**
   ```bash
   # Elige el script correspondiente a tu proveedor:
   export GITHUB_TOKEN="<tu PAT>"
   ./scripts/create-remote-repo-github.sh --repo-path mi-usuario/mi-repo

   aws secretsmanager put-secret-value --secret-id <git_remote_token_secret_arn de outputs.tf> --secret-string "$GITHUB_TOKEN"
   git push origin develop   # o main
   ```

A partir de aquí, los cambios al módulo `modules/app-infra` (o lo que quieras desplegar) se aplican
solos vía el pipeline correspondiente.

### Cambiar de cuenta destino más adelante (rotación)

Solo se toca `scripts/set-cross-account-target.sh` + un `terraform apply` de `pipeline/` (para que
la policy de IAM de CodeBuild se resincronice con el ARN nuevo):

```bash
./scripts/set-cross-account-target.sh --project mi-proyecto --environment dev --role-arn <nuevo-arn>
cd pipeline && terraform apply
```

No hace falta tocar `environments/*`, `modules/*`, ni ningún otro `.tf`.

---

## 4. Git remoto (agnóstico al proveedor)

El repositorio remoto (destino del mirror) **no es un recurso de Terraform**, y el pipeline
**no sabe a qué plataforma está empujando**. La separación es:

| Componente | ¿Agnóstico? | Por qué |
|---|---|---|
| `buildspecs/mirror.yml` | Sí, 100% | Solo usa `git fetch` / `git push --mirror` — protocolo Git puro, HTTP Basic Auth genérica (`https://git:<token>@host/path.git`). Funciona igual contra GitHub, GitLab, Bitbucket, Gitea... |
| `pipeline/variables.tf` (`git_remote_host`, `git_remote_path`) | Sí | Son solo strings; no asumen ninguna API concreta. |
| `scripts/create-remote-repo-*.sh` | No, por necesidad | Crear un repo es una operación de la API REST propia de cada plataforma — el protocolo Git no lo cubre (ver decisión en sección 1). |

Para cambiar de proveedor:
1. Actualiza `git_remote_host` y `git_remote_path` en `pipeline/terraform.tfvars` y aplica.
2. Genera un token del nuevo proveedor y rellena el secret (`git_remote_token_secret_arn`).
3. Ejecuta el script de creación correspondiente al nuevo proveedor (o escribe uno nuevo si no
   existe todavía en `scripts/`, siguiendo el patrón de los existentes).

Nada de `buildspecs/mirror.yml` ni del resto del pipeline necesita cambiar.

---

## 5. Cross-account (Opción A: SSM como fuente de verdad externa)

- `pipeline/secrets.tf` declara `data "aws_ssm_parameter" "target_role_arn"` por entorno — **lee**,
  no escribe.
- `pipeline/iam.tf` usa esos valores para la policy `sts:AssumeRole` del rol de CodeBuild.
- `buildspecs/plan.yml` y `buildspecs/apply.yml` leen el mismo parámetro en runtime para hacer el
  `aws sts assume-role`.
- **El único punto para definir o rotar esta configuración es `scripts/set-cross-account-target.sh`**
  (que a su vez solo hace `aws ssm put-parameter`). No hay que tocar `.tfvars` ni ningún `.tf`.
- Tras cambiar el parámetro, se necesita un `terraform apply` de `pipeline/` para que la policy IAM
  de CodeBuild conozca el ARN nuevo (medida de seguridad: la policy nunca autoriza más ARNs que los
  vistos en el último apply).

---

## 6. Qué necesitas rellenar antes de aplicar

- `bootstrap/terraform.tfvars`: `project_name` (Fase 0).
- `pipeline/terraform.tfvars`: `project_name` (mismo valor que en bootstrap), `git_remote_host`,
  `git_remote_path`, nombres de backend (`tf_state_bucket`, `tf_state_lock_table` — son los outputs
  de `bootstrap/`).
- Rol cross-account en cada cuenta destino (Fase 1) + su publicación en SSM (Fase 2).
- Token del proveedor Git remoto en Secrets Manager (Fase 4) — **nunca en código ni en `.tfvars`**.

Todo lo demás ya está parametrizado con valores por defecto sensatos.
