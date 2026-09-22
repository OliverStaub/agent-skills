---
name: codebase-diagrams
description: Generate architecture and onboarding diagrams for an existing codebase - a C4 model (System Context, Container, Component, Deployment, Dynamic views) written in Structurizr DSL and rendered to PNG/SVG, plus free-form D2 diagrams for infrastructure topology, business-logic flows, request sequences, data models and module dependencies. Use this whenever someone wants to understand, document, visualise or get onboarded onto a codebase, asks for "architecture diagrams", "C4", "Structurizr", "D2", "system overview", "how does this service work", "draw the infrastructure", "sequence diagram of X", "data model diagram", or wants docs/architecture material - even if they don't name a diagram type. Also use it to update diagrams that were previously generated with it.
---

# Codebase diagrams (C4 via Structurizr + free-form via D2)

The goal is a small set of diagrams that let a newcomer understand a codebase quickly: what the
system is and who uses it, what runs where, how the important pieces talk to each other, and how
the core business flows work. Two tools, deliberately:

- **Structurizr DSL** for the C4 model. One `workspace.dsl` is the source of truth for the static
  structure; views are exported to PNG + SVG with the Structurizr renderer.
- **D2** for everything C4 is bad at: infrastructure/network topology, business-process flows,
  sequence diagrams, ER/data models, module dependency graphs, CI/CD pipelines.

Output is **sources + rendered images only** (no explanatory Markdown unless asked), laid out as:

```
<target>/                      default: docs/architecture/
  workspace.dsl                C4 model (all views)
  c4/                          exported images, one PNG + SVG per view
  d2/                          <name>.d2 next to <name>.svg and <name>.png
```

Bundled resources:
- `scripts/preflight.sh` – verifies the toolchain end-to-end (mandatory first step)
- `scripts/render-c4.sh <dir>` – validate `workspace.dsl` and export PNG + SVG into `c4/`
- `scripts/render-d2.sh <dir>` – format, validate and render every `.d2` in `d2/`
- `references/structurizr-dsl.md` – DSL syntax, views, styles, validation rules, full example
- `references/d2.md` – D2 syntax, shapes, sequence/sql_table, layout advice, examples
- `references/codebase-exploration.md` – how to find C4 elements and diagram-worthy flows in code
- `assets/workspace-template.dsl` – starting skeleton for a new workspace

## Step 0 – Preflight (never skip, never work around)

Run the preflight before touching the codebase:

```bash
bash <skill-dir>/scripts/preflight.sh
```

It locates a Playwright-enabled Structurizr build, checks `d2`, and does a real trial export of a
tiny workspace and a tiny D2 file to PNG. It prints the exact install commands for anything
missing and exits non-zero.

**Docker is the preferred way to run Structurizr** (`structurizr/structurizr:<version>-playwright`):
it is the only route that guarantees the Playwright-enabled build, needs no local Java, and behaves
the same on every machine and in CI. The scripts resolve Structurizr in this order: `$STRUCTURIZR_CMD`
→ `$STRUCTURIZR_USE_DOCKER=1` → `$STRUCTURIZR_WAR` / `~/.structurizr/structurizr.war` → a running
Docker daemon with the Playwright image → a `structurizr` binary on PATH (last, because the Homebrew
formula builds the war without Playwright and cannot export images). The preflight prints which one
it picked; if the user expects Docker and something else was chosen, tell them to set
`STRUCTURIZR_USE_DOCKER=1`. Docker's first run pulls the image (a few hundred MB), so allow time.

If it fails: **stop**. Show the user the preflight output and ask them to install what is
missing (or to point you at the tools via the environment variables it names). Do not fall back to
Mermaid, PlantUML, hand-written SVG or images-less output, and do not attempt to install system
packages or download binaries yourself unless the user explicitly asks you to. The user chose this
toolchain so that the diagrams are reproducible on their machine and in CI; a silent fallback
produces artefacts nobody can regenerate. A first run may take a few minutes while Structurizr's
Playwright downloads Chromium - that is expected, tell the user and wait.

Re-run the preflight after the user reports installing something; only continue once it passes.

## Step 1 – Agree the scope (briefly)

Most requests are answerable with sensible defaults, so ask only when a wrong guess is expensive:

- **Which system?** A repo with one deployable is one software system. A monorepo with many
  services is usually still *one* software system with many containers (services are containers
  in C4 terms) - unless the services are owned by different teams and released independently, in
  which case ask which one to model, or model the landscape. Mixing these up produces diagrams
  that mislead newcomers, so ask if it isn't obvious from the repo layout.
- **Depth.** Default: System Context + Container for the system, Component view for the one or two
  containers where most business logic lives, Deployment view when infrastructure definitions
  exist (Dockerfiles, compose, k8s, Terraform, Helm, serverless configs), one or two Dynamic views
  for the most important runtime flows. Component views of every container are noise.
- **Target directory.** Default `docs/architecture/`. If a `workspace.dsl` already exists anywhere
  in the repo, extend it (keep its view keys, identifiers and styles) instead of creating another.

State the choices you made in one or two sentences before starting the exploration so the user can
redirect early.

## Step 2 – Explore the codebase before drawing anything

Read `references/codebase-exploration.md` and follow it. The point is to collect *evidence*, not to
guess from folder names. Keep a scratch table (not committed) of every element and relationship
you intend to draw, with the file(s) that prove it:

```
element/relationship                       | kind        | evidence
Web App -> API "calls" "HTTPS/JSON"        | rel         | web/src/api/client.ts:12, api/routes/*.py
API -> Postgres "reads/writes" "SQL/psycopg" | rel       | api/db/session.py, alembic/versions/
Stripe (external)                          | softwareSys | api/payments/stripe_client.py, env STRIPE_*
```

Things a diagram must never contain: elements you inferred but could not find in code or config,
relationships whose direction you did not check (who initiates the call?), technology labels
copied from a README that the lockfiles contradict. If something is important but unverifiable
(e.g. an external system referenced only by a hostname), include it tagged `Unverified` and list
it in the final report so the user can confirm.

While exploring, also note candidate free-form diagrams (Step 5): the 1-3 request paths that
touch the most containers, the core domain entity and its lifecycle/state machine, the data model,
anything with a non-trivial infrastructure topology, and (for monorepos) the module dependency
structure.

## Step 3 – Write `workspace.dsl`

Read `references/structurizr-dsl.md` (at minimum sections 2-7 and 9) before writing. Start
from `assets/workspace-template.dsl` when there is no existing workspace. Conventions that make
the resulting diagrams useful for onboarding:

- `!identifiers hierarchical`, camelCase identifiers, display names as a newcomer would say them
  ("Order Service", not "order-svc-v2"), technology strings from the actual lockfiles/base images
  ("Spring Boot 3 / Java 21", "PostgreSQL 16").
- Every relationship has a verb phrase *and* a technology: `"Publishes order events to" "Kafka"`.
  "Uses" tells a newcomer nothing.
- Tag data stores `Database`, brokers/queues `Queue`, third-party systems `External`, browser
  front-ends `Browser`, mobile apps `Mobile`; the template's styles key off these tags.
- Explicit, stable view keys (`SystemContext`, `Containers`, `Components-Api`,
  `Deployment-Production`, `Dynamic-Checkout`). Auto-generated keys change between runs and break
  links and any manual layout.
- `autoLayout` on every view. Pick the direction that suits the flow (`lr` for pipelines and
  request paths, `tb` for layered systems). Use `exclude` and `*?` to keep each view at roughly
  5-15 elements; if a container view needs more, split by `group` or add a filtered view instead.
- Descriptions on elements are one line about *responsibility*, not implementation trivia.
- Component views: components are the major internal building blocks a newcomer navigates by
  (modules, bounded contexts, layers) - typically 5-12 per container, each mapped to a directory
  or package. Never one component per class or file.
- Deployment view: model the real environment (nodes = k8s cluster/namespace/pod, cloud
  account/region/service, VM, container runtime) and attach `containerInstance`s. Use the built-in
  cloud/k8s themes listed in the reference if the tags match.
- Dynamic views: one per key flow, 4-10 steps, each step an instance of a relationship that exists
  in the static model, with the step text describing *this* interaction ("Reserves stock for the
  order").

## Step 4 – Validate and render the C4 views

```bash
bash <skill-dir>/scripts/render-c4.sh <target-dir>
```

The script runs `validate` first and prints the parser error with its line number; fix and
re-run until clean. It then exports every view to `<target>/c4/` as PNG and SVG.

Then **look at the images** (open the PNGs with your file-reading tool). Check: all expected views
exported, no view is an unreadable hairball, labels are not truncated, external systems are
visually distinct, arrows point in the direction of the initiator. Fix by adjusting
`autoLayout` direction/separation, excluding elements, splitting views, or shortening labels -
not by dropping information the newcomer needs. Re-render after each change.

## Step 5 – Decide which free-form diagrams earn their place

Each D2 diagram must answer one concrete question a newcomer asks. Aim for 3-6 in total; pick
from this table based on what the exploration found, and skip anything the C4 views already
answer well:

| Question | Diagram | D2 idiom | When it is worth it |
|---|---|---|---|
| "What actually runs where, and how does traffic get in?" | Infrastructure topology | containers for cloud/account/VPC/cluster, `cloud`/`cylinder`/`queue` shapes, `--layout elk` | Networking, multiple environments, CDN/DNS/WAF, IaC present. The C4 deployment view shows the logical mapping; this one shows the real topology. |
| "What happens when a user does X?" | Sequence diagram | `shape: sequence_diagram`, spans, groups for error paths | The 1-3 flows that cross the most containers or have tricky failure handling |
| "How does the core business process work?" | Flowchart / swimlanes | containers as lanes, `diamond` decisions, `oval` terminals | Multi-step domain processes (checkout, claims, onboarding, approval) |
| "What states can the main entity be in?" | State diagram | shapes as states, labelled edges as transitions | An entity with an explicit status/state field and guarded transitions |
| "What is the data model?" | ER diagram | `sql_table` with PK/FK, FK edges | ORM models / migrations / schema files exist; cap at the ~10-20 central tables |
| "How do the modules/packages depend on each other?" | Dependency graph | one shape per module, `--layout elk`, classes for layers | Monorepos, layered architectures, when import cycles matter |
| "How does code get to production?" | CI/CD pipeline | `step` shapes left-to-right | Non-trivial pipelines (multi-stage, environments, gates) |
| "How are events/messages routed?" | Messaging topology | `queue` shapes, producers/consumers, classes for topics | Event-driven systems with more than a couple of topics |

Tell the user which ones you chose and why in one line each.

## Step 6 – Write and render the D2 diagrams

Read `references/d2.md` (sections 2, 4-5 always; 6, 8 when using sql_table or sequence
diagrams; 11 before rendering). One file per diagram in `<target>/d2/`, kebab-case names that say
what the diagram answers (`infra-production.d2`, `seq-checkout.d2`, `flow-order-lifecycle.d2`,
`er-core-schema.d2`, `deps-modules.d2`).

Conventions:
- Put a title at the top as a `text` shape or use `title: |md # ... |` style header, and keep
  labels short; move detail into `tooltip` rather than the label.
- Define `classes` for semantics used more than once (`external`, `database`, `queue`, `async`,
  `deprecated`) so styling is consistent across all diagrams; keep the same colours as the C4
  styles where the concepts overlap (external systems grey, data stores cylinder, etc.).
- Use `direction: right` for flows and pipelines, `down` for layered structures; switch to
  `--layout elk` (set in the file via `vars: { d2-config: { layout-engine: elk } }`) for nested
  infrastructure and dependency graphs.
- Every arrow is labelled with what flows or why (protocol, event name, condition).
- Nothing in a D2 diagram may contradict the C4 model - same names for the same things.

Render with:

```bash
bash <skill-dir>/scripts/render-d2.sh <target-dir>
```

It formats (`d2 fmt`), validates, and renders each `.d2` to SVG and PNG next to the source.
Then look at each PNG and fix layout problems (crossings, overlaps, unreadable size) with
direction changes, containers, or the ELK engine before declaring done.

## Step 7 – Final check and report

Before reporting, verify:

- [ ] Preflight passed in this session; every image was produced by the scripts, not by hand
- [ ] Every element and relationship in `workspace.dsl` traces to evidence you saw
- [ ] `render-c4.sh` and `render-d2.sh` both exit 0 on the final sources (re-run them once more)
- [ ] Each view/diagram is legible at a glance (you looked at every PNG)
- [ ] Same name for the same thing across C4 and D2; technology labels match the lockfiles
- [ ] No diagram exceeds roughly 15-20 elements; larger ones were split
- [ ] Elements you could not verify are tagged `Unverified` and listed below

Report to the user in this shape (short, no recap of the steps):

1. Which system/scope was modelled and any assumption that could be wrong.
2. The file list with one line per diagram: what question it answers.
3. Open points: unverified elements, flows you saw but did not diagram, suggested follow-ups
   (e.g. "the payment retry logic in `worker/retry.py` deserves its own state diagram").
4. How to regenerate: the two script commands (or the equivalent raw `structurizr`/`d2`
   commands if the user wants them in CI).

## Updating existing diagrams

When the repo already contains a `workspace.dsl` or `d2/` sources from an earlier run: re-run the
preflight, read the existing sources first, then diff the codebase against them. The bar for
touching anything is **a real divergence between code and diagram**: a container, external system,
component, relationship or flow that was added, removed, renamed or re-wired; a technology that
changed (framework, database, broker); a deployment topology that moved; a business flow whose
steps changed. If nothing like that has happened, change nothing - do not re-render, do not
re-flow layouts, do not polish wording, colours or ordering - and report that the diagrams are
still accurate, listing what you checked. Churn in diagram sources without a substantive reason
makes reviewers stop trusting the diffs, and re-rendered images with only pixel-level differences
pollute the repo history.

When something did change, make the minimal edit that fixes it, keep identifiers, view keys and
styles stable, re-render (the scripts regenerate all views; that is fine, but do not hand-edit
unaffected sources), and list each change with its evidence in the report. Only regenerate from
scratch if the user asks or the existing model is clearly unrelated to the current code.
