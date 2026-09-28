---
name: codebase-diagrams
description: Generate a curated set of architecture/onboarding diagrams for a codebase - C4 views in Structurizr DSL plus D2 diagrams (infra, flows, sequences, data models, dependencies), rendered to SVG/PNG. Also updates previously generated diagrams.
disable-model-invocation: true
---

# Codebase diagrams (C4 via Structurizr + free-form via D2)

The goal is the **smallest set of diagrams that lets a newcomer understand a codebase quickly**:
what the system is, what runs and how the pieces talk, and how the one or two flows that matter
actually work. A handful of diagrams that are each correct, finished and worth opening beats a
folder of a dozen that nobody reads - every extra diagram dilutes the good ones and is one more
thing that goes stale. Two tools, deliberately:

- **Structurizr DSL** for the C4 model. One `workspace.dsl` is the source of truth for the static
  structure; views are exported with the Structurizr renderer.
- **D2** for the few things C4 is bad at: infrastructure topology, business-process flows,
  sequence diagrams, data models, module dependency graphs.

Output is **sources + rendered images only** (no explanatory Markdown unless asked):

```
<target>/                      agreed with the user in Step 3 (suggest docs/architecture/)
  workspace.dsl                C4 model (all views)
  c4/                          one SVG per view (generated - replaced on every render)
  d2/                          <name>.d2 next to <name>.svg
```

Images are SVG by default (small, sharp, render on GitHub/GitLab). Pass `--format png` or
`--format both` to the render scripts if the user wants PNGs committed. Either way the scripts
write PNG previews to a scratch folder outside the repo for you to look at.

Bundled resources:

- `scripts/preflight.sh` – verifies the toolchain end-to-end (mandatory first step)
- `scripts/render-c4.sh <dir> [--format svg|png|both]` – validate `workspace.dsl`, export views into `c4/`
- `scripts/render-d2.sh <dir> [--format svg|png|both]` – format, validate and render every `.d2` in `d2/`
- `references/structurizr-dsl.md` – DSL syntax, views, styles, validation rules, full example
- `references/d2.md` – D2 syntax, shapes, sequence/sql_table, layout advice, examples
- `references/codebase-exploration.md` – how to find C4 elements and diagram-worthy flows in code
- `assets/workspace-template.dsl` – starting skeleton for a new workspace

## Step 0 – Preflight (never skip, never work around)

Run the preflight from the root of the project you are diagramming, before touching the codebase:

```bash
cd <project-root> && bash <skill-dir>/scripts/preflight.sh
```

It puts its trial workspace inside that project (in the skill folder if the skill is installed in
the project, else `<project>/.claude/tmp/`, removed again afterwards), so a pass also proves Docker
can see the directory the real renders will write to.

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

One failure is not a missing tool: "Docker cannot see <project>". The Docker VM does not share
that path (typical on Colima, which shares only `$HOME` by default), so the container sees an empty
directory. Relay the fix options the preflight prints instead of install instructions.

Re-run the preflight after the user reports installing something; only continue once it passes.

## Step 1 – Look for existing diagrams

Before exploring, check whether the repo already has architecture diagrams:
`find . -name '*.dsl' -o -name '*.d2' -o -name '*.puml' -o -name '*.mmd' -o -name '*.drawio'`
(skip `node_modules`, `vendor`, build output), plus `docs/`, `architecture/`, `ARCHITECTURE*`.

- **A `workspace.dsl` or `d2/` folder from this skill exists** → that directory is the target;
  follow "Updating existing diagrams" at the end of this file instead of the steps below.
- **Other diagrams exist** (PlantUML, Mermaid, draw.io, images in `docs/`) → their location is the
  natural home; propose putting the new sources next to them, and reuse their names for things.
- **Nothing exists** and the user did not say where → you will ask in Step 3. Don't pick a folder
  silently: where docs live is a team convention (`docs/`, `doc/architecture/`, a separate docs
  repo, a wiki export folder...) and a wrong guess means the user has to move files and fix links.

If the user already named a location in their request, use it and don't ask.

## Step 2 – Explore the codebase before deciding anything

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

Also decide **which system** you are modelling. A repo with one deployable is one software system.
A monorepo with many services is usually still *one* software system with many containers - unless
the services are owned by different teams and released independently; then ask which one to model.

While exploring, note *candidate* diagrams - flows, entities, topologies that might be worth
drawing. Candidates are cheap; Step 3 is where most of them get cut.

## Step 3 – Plan a small diagram set, then confirm it (and the location) with the user

This is the step that decides whether the output is useful, so think it through rather than
drawing everything the exploration surfaced. Start from the questions a new developer on *this*
codebase would actually ask in their first week, then pick the fewest diagrams that answer them.

**Budget: usually 3-5 diagrams in total** (C4 views and D2 diagrams combined). A small service or
library may need 2; a large distributed system may justify 6-7. Going beyond that needs the user
to ask for it. If you find yourself planning more, you are drawing things because you *can*, not
because someone needs them.

**The default core** - start here and add only what passes the tests below:

1. **Container view** - almost always. It is the single most useful architecture diagram.
2. **System Context view** - only if it shows something the container view doesn't: several user
   roles or several external systems. With one user and zero or one external system, skip it; the
   container view already shows that.
3. **One diagram for the most important runtime flow** - the request path or business process a
   newcomer is most likely to touch or break. Either a C4 dynamic view or a D2 sequence diagram,
   not both for the same flow.

**Every further candidate must pass all four tests**, otherwise leave it out (and mention it as a
possible follow-up in the report):

- *Real question*: you can name the concrete question it answers ("how does a payment get retried
  after a webhook fails?"), not a category ("data model").
- *Not already answered*: no other planned diagram shows substantially the same thing. Two
  deployment views that differ in one box, or a dependency graph that restates the component
  view, fail this test.
- *Enough substance*: there is real structure to show - branching, several participants, a
  non-obvious topology, 5+ meaningful elements. A three-box flow is a sentence, not a diagram.
- *It is a diagram*: information that is really a table (permission matrices, env-var lists,
  config options), a list, or prose does not belong in D2 - drop it from the plan.

Typical additions that often pass, when the code gives them substance:

| Question | Diagram | When it earns its place |
| --- | --- | --- |
| "What's inside the main service?" | C4 Component view | The one container where most business logic lives *and* its internal modules are non-obvious. Never for every container. |
| "What actually runs where?" | C4 Deployment view *or* D2 infra topology (not both) | IaC/k8s/cloud config defines a non-trivial production topology. Model production only, not each environment. |
| "What states can the main entity be in?" | D2 state diagram | An explicit status field with guarded transitions spread across the code. |
| "What is the data model?" | D2 ER diagram (`sql_table`) | Real schema/migrations with 5+ related tables; cap at the ~10-15 central ones. |
| "How are events routed?" | D2 messaging topology | Event-driven system with more than a couple of topics. |
| "How do modules depend on each other?" | D2 dependency graph | Monorepos/layered systems where the rules or cycles matter and no component view covers it. |

**Then stop and confirm with the user** in one short message (use the AskUserQuestion tool if
available). Show the plan as a list - one line per diagram: name, the question it answers - plus
one line listing the candidates you deliberately left out. If Step 1 found no existing diagram
location, ask where to save them in the same message, offering `docs/architecture/` as the
default and any existing docs folder you spotted as alternatives. One round of questions, not
several. Proceed once the user answers; if they add or drop diagrams, adjust the plan.

If you are running non-interactively (no way to get an answer), use the default location and the
plan as drafted, and state both at the top of the final report.

## Step 4 – Write `workspace.dsl`

Read `references/structurizr-dsl.md` (at minimum sections 2-7 and 9) before writing. Start
from `assets/workspace-template.dsl` when there is no existing workspace, and only define the
views that are in the agreed plan - the model can contain more elements than any one view shows,
but every view in the file gets exported, so an unplanned view becomes an unplanned file.
Conventions that make the resulting diagrams useful for onboarding:

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
- Deployment view (if planned): model production - or the one environment the user cares about -
  not every environment. Nodes are k8s cluster/namespace/pod, cloud account/region/service, VM or
  container runtime, with `containerInstance`s attached. Use the built-in cloud/k8s themes listed
  in the reference if the tags match.
- Dynamic views (if planned): only for the flow(s) in the plan, 4-10 steps, each step an instance
  of a relationship that exists in the static model, with the step text describing *this*
  interaction ("Reserves stock for the order").

## Step 5 – Render and check the C4 views

```bash
bash <skill-dir>/scripts/render-c4.sh <target-dir>
```

The script runs `validate` first and prints the parser error with its line number; fix and
re-run until clean. It then replaces `<target>/c4/` with one image per view (Structurizr's
automatic `-key` legend images are dropped) and prints the folder with PNG previews.

Then **look at every preview PNG** with your file-reading tool. Check: all planned views exported,
no view is an unreadable hairball, labels are not truncated, external systems are visually
distinct, arrows point in the direction of the initiator. Fix by adjusting `autoLayout`
direction/separation, excluding elements, or shortening labels - not by dropping information the
newcomer needs. Re-render after each change.

## Step 6 – Write and render the D2 diagrams from the plan

Read `references/d2.md` (sections 2, 4-5 always; 6, 8 when using sql_table or sequence
diagrams; 11 before rendering). One file per planned diagram in `<target>/d2/`, kebab-case names
that say what the diagram answers (`seq-checkout.d2`, `flow-order-lifecycle.d2`, `er-core-schema.d2`).

**Finish one diagram before starting the next**: write it, render it, look at the preview, fix it.
Writing all sources first and rendering at the end is how half-done diagrams end up in the repo.
If a planned diagram turns out not to be worth it once you draw it (too thin, duplicates another),
delete its source and mention it in the report rather than shipping a weak one.

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

It formats (`d2 fmt`), validates, and renders each `.d2` next to its source, writes previews to
the scratch folder, and warns about images whose `.d2` source no longer exists. Look at each
preview and fix layout problems (crossings, overlaps, unreadable size) with direction changes,
containers, or the ELK engine before moving on.

## Step 7 – Final check and report

Before reporting, verify:

- [ ] Preflight passed in this session; every image was produced by the scripts, not by hand
- [ ] The files on disk are exactly the agreed plan - no extra views, no leftover or orphan files
      (`find <target> -type f` and compare)
- [ ] Every element and relationship in `workspace.dsl` traces to evidence you saw
- [ ] `render-c4.sh` and `render-d2.sh` both exit 0 on the final sources (re-run them once more)
- [ ] Each diagram is finished and legible at a glance (you looked at every preview)
- [ ] Same name for the same thing across C4 and D2; technology labels match the lockfiles
- [ ] No diagram exceeds roughly 15-20 elements; larger ones were split
- [ ] Elements you could not verify are tagged `Unverified` and listed below

Report to the user in this shape (short, no recap of the steps):

1. Which system/scope was modelled, where the files are, and any assumption that could be wrong.
2. One line per diagram: file and the question it answers.
3. Open points: unverified elements, and the candidates you left out with a one-line reason each
   (e.g. "payment retry state machine in `worker/retry.py` - worth a state diagram if you work on
   billing"). The user can ask for any of them later.
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

Keep the image format the repo already uses: if the existing `c4/` or `d2/` folders contain PNGs,
pass `--format png` (or `both`) to the render scripts - the default `svg` would replace them.

When something did change, make the minimal edit that fixes it, keep identifiers, view keys and
styles stable, re-render (the scripts regenerate all views; that is fine, but do not hand-edit
unaffected sources), and list each change with its evidence in the report. Only regenerate from
scratch if the user asks or the existing model is clearly unrelated to the current code.
