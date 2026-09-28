# Exploring a codebase to find what to draw

The diagrams are only as good as the evidence behind them. This file lists where the C4 elements
and the diagram-worthy flows usually hide, so exploration is systematic rather than a walk through
whatever directory is opened first. Work top-down: repo shape → deployables → boundaries → talk
paths → the flows a newcomer needs.

## 1. Repo shape (5 minutes)

- Top-level listing, `README*`, `CONTRIBUTING*`, `docs/`, `ARCHITECTURE*`, `ADR*/adr/` — read
  them but treat claims as hypotheses to verify; READMEs go stale.
- Workspace/monorepo markers: `pnpm-workspace.yaml`, `package.json#workspaces`, `nx.json`,
  `turbo.json`, `lerna.json`, `go.work`, `Cargo.toml [workspace]`, `settings.gradle` (`include`),
  Maven `<modules>`, `pyproject.toml` with multiple packages, Bazel `WORKSPACE`/`MODULE.bazel`.
- Existing diagrams: `*.dsl`, `*.puml`, `*.mmd`, `*.d2`, `*.drawio`, `docs/**/*.png` — reuse names.
- Git activity for hot spots: `git log --since="6 months ago" --name-only --pretty=format: | sort | uniq -c | sort -rn | head -40`.

## 2. Deployables → containers

A C4 container is something that must be running for the system to work: a process, an app, a
data store, a broker, a serverless function group, a CLI that runs as a job. Find them from:

| Signal | Where |
|---|---|
| Docker images | `Dockerfile*`, `docker-compose*.yml` (`services:` = candidate containers, `image:` = technology, `depends_on`/env vars = relationships) |
| Kubernetes / Helm | `k8s/`, `deploy/`, `charts/`, `kustomization.yaml`: `Deployment`, `StatefulSet`, `CronJob`, `Job`, `Ingress`, `Service`; `image:` fields |
| IaC | `*.tf` (`aws_lambda_function`, `aws_ecs_service`, `aws_rds_*`, `google_cloud_run_*`, `azurerm_*`), Pulumi, CDK, `serverless.yml`, `sam-template.yaml`, `fly.toml`, `render.yaml`, `Procfile`, `app.yaml` |
| Process entry points | `main.go`, `cmd/*/main.go`, `src/main/java/**/*Application.java`, `manage.py`, `wsgi.py`/`asgi.py`, `bin/*`, `package.json#scripts.start`, `__main__.py`, `Program.cs` |
| Front-ends | `next.config.*`, `vite.config.*`, `angular.json`, `ios/`, `android/`, `app.json` (Expo), `pubspec.yaml` |
| Data stores | ORM config (`DATABASE_URL`, `spring.datasource`, `settings.DATABASES`, `prisma/schema.prisma` `datasource`), migration dirs (`alembic/`, `migrations/`, `db/migrate/`, `flyway`, `liquibase`), Redis/Mongo/Elastic client init |
| Brokers/queues | `kafka`, `rabbitmq`/`amqp`, `sqs`, `pubsub`, `nats`, `celery` broker config, `bullmq`, `sidekiq` |
| Scheduled/batch | `CronJob`, `celery beat`, `@Scheduled`, `cron` in compose, GitHub Actions `schedule:` that run app code |

Rule of thumb: if `docker-compose.yml` exists, its services are a very good first draft of the
container view - then confirm each one is actually referenced by code.

## 3. People and external systems (System Context)

- **People**: roles in auth code (`roles`, `permissions`, `is_staff`, `@PreAuthorize`), route
  groups (`/admin`, `/api/v1/partner`), UI apps per audience, support/ops tooling. Model roles
  a newcomer must know (End user, Admin, Support agent, Partner developer), not every permission.
- **External systems**: SDK dependencies in lockfiles (`stripe`, `twilio`, `sendgrid`,
  `@aws-sdk/*`, `googleapis`, `auth0`, `okta`, `launchdarkly`, `segment`, `sentry`,
  `datadog`, `openai`), env var names (`*_API_KEY`, `*_URL`, `*_ENDPOINT`), hostnames in config,
  OAuth/OIDC issuers, webhook handlers (inbound integrations - direction matters!), SMTP config,
  payment/shipping/tax providers, upstream data feeds.
- Distinguish **external systems the business depends on** (Stripe, the ERP) from
  **observability/infra plumbing** (Sentry, Datadog). The former go on the context diagram; the
  latter usually only on the D2 infrastructure diagram, or nowhere.

## 4. Relationships (who calls whom, how)

For each candidate relationship, find the initiating side in code:

- HTTP clients: `fetch(`, `axios`, `httpx`/`requests`, `RestTemplate`/`WebClient`, `net/http`,
  generated OpenAPI/gRPC clients; base URLs in config tell you the target.
- Service discovery names in k8s manifests / compose (`http://orders:8080`).
- Messaging: producers (`publish`, `send`, `emit`, `produce`) vs consumers (`subscribe`,
  `@KafkaListener`, `consumer.poll`, `@RabbitListener`, `sqs.receive`). Draw producer → broker
  and broker → consumer (or producer → consumer labelled with the topic, if the broker is not
  a container in its own right).
- Database access: which containers import the ORM/session module or hold the connection string.
  Shared databases between services are an important thing to make visible.
- Webhooks/callbacks: external system → API (inbound). Cron/poll: API → external (outbound).
- Auth flows: browser → IdP → API token validation.

Record technology for each: protocol + format (`JSON/HTTPS`, `gRPC`, `SQL/JDBC`, `AMQP`,
`Kafka topic orders.created`, `S3 API`).

## 5. Components (inside the main container(s))

Only for containers where the business logic lives. Components are the units a newcomer navigates
by - typically the top-level packages/modules under `src/`, `app/`, `internal/`, `pkg/`,
`com.company.product.*`. Good component boundaries:

- Layered apps: `api/routes`, `services`/`application`, `domain`, `repositories`/`persistence`,
  `integrations`/`clients`, `jobs`.
- Modular monoliths / DDD: one component per bounded context/module (`billing`, `catalog`,
  `identity`), plus shared kernel.
- Frameworks with conventions: Django apps, Rails engines, NestJS modules, Spring `@Configuration`
  groups, Go packages under `internal/`.

Find dependencies between components from imports (`rg "^from app\.(\w+)" -o`, `go list -deps`,
`jdeps`, `madge`, `pydeps`, `dependency-cruiser` if available - but plain `rg` on import lines is
usually enough). Note cyclic dependencies; they are worth showing.

## 6. Deployment

Only if the repo defines it (see IaC/k8s rows above). Map: cloud account/region → cluster/VPC →
node/service (k8s Deployment, ECS service, Lambda, Cloud Run, VM) → `containerInstance`. Capture
replica counts, managed services (RDS, ElastiCache, SQS) as deployment nodes with the container
instance inside, and edge components (ALB/Ingress/CDN/WAF) as `infrastructureNode`s. If several
environments exist, model production (or the one the user cares about) and mention the others.

## 7. Business logic and flows (for D2)

Newcomers ask "what happens when …". Find the flows that matter:

- **Entry points with the most fan-out**: a route/handler that calls several services, publishes
  events and writes to the DB → sequence diagram.
- **Core entity lifecycle**: the model with a `status`/`state` enum and code that transitions it
  (`order.status = ...`, state-machine libraries, `transition` methods) → state diagram.
- **Multi-step business processes**: sagas/orchestrators, workflow engines (Temporal, Step
  Functions, Camunda), long handler chains with branches → flowchart/swimlanes; lanes = the
  container or role that performs each step.
- **Data model**: ORM models/entities, `schema.prisma`, migrations, `schema.sql`, protobuf
  messages. Pick the central 10-20 tables around the core entity; show PK/FK and cardinality.
- **Integration choreography**: which events exist, who emits, who consumes (grep topic names).
- **Pipelines**: CI workflow files (`.github/workflows`, `.gitlab-ci.yml`, `Jenkinsfile`,
  `azure-pipelines.yml`) when the path to production has multiple stages/environments/gates.

For each chosen flow, read the actual code path end to end (handler → service → repo → client) and
write the steps down with file:line references before drawing. Include the unhappy path if the
code handles it explicitly (retries, compensations, dead-letter queues) - that is exactly what
onboarding docs usually omit and newcomers get bitten by.

## 8. Sizing and honesty

- Prefer fewer, correct elements over completeness. A container view with 8 boxes that a
  newcomer trusts beats one with 25 that nobody reads.
- When the code and the docs disagree, the code wins; mention the discrepancy in the report.
- When something cannot be verified (a hostname with no client code, a service mentioned only in
  comments), either leave it out or tag it `Unverified` and list it for the user.
- Do not run the application, hit external endpoints or read secrets to "verify" anything; static
  reading of code and config is the scope.
