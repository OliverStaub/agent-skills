# Structurizr DSL reference (for writing `workspace.dsl` from a codebase)

Sources: docs.structurizr.com (dsl/language, dsl/basics, dsl/identifiers, dsl/expressions,
dsl/implied-relationships, dsl/defaults, dsl/cookbook/*, workspaces/scope, workspaces/recommendations,
validate, export, export/png-and-svg, export/static-site, binaries, local, inspect,
server/diagrams/notation, server/diagrams/themes). Verified September 2026 against the unified
`structurizr` tool (release 2026.09.19).

## Contents

1. [Tool commands](#1-tool-commands)
2. [Minimal workspace skeleton](#2-minimal-workspace-skeleton)
3. [Model elements](#3-model-elements)
4. [Relationships](#4-relationships)
5. [Deployment modelling](#5-deployment-modelling)
6. [Views](#6-views)
7. [Styles and themes](#7-styles-and-themes)
8. [Documentation and ADRs](#8-documentation-and-adrs)
9. [Validation rules and common errors](#9-validation-rules-and-common-errors)
10. [Complete example workspace](#10-complete-example-workspace)

---

## 1. Tool commands

One binary, many sub-commands: `validate`, `export`, `local`, `inspect` (plus server/cloud commands:
`push pull lock unlock merge list create delete branches generate playground`). Requires **Java 21**.

| Form | Command |
|---|---|
| Java | `java -jar structurizr.war <command> [params]` |
| Docker | `docker run -it --rm -v $PWD:/usr/local/structurizr structurizr/structurizr <command> [params]` |

Binaries: `structurizr-<ver>.war` / `structurizr.war` (no Playwright), `structurizr-<ver>-playwright.war`
(Playwright bundled; needed for PNG/SVG). Docker tags: `latest`, `<ver>`, `<ver>-noble`, `<ver>-playwright`,
`preview`. Inside Docker the data directory is `/usr/local/structurizr`, so mount `$PWD` there and
reference files by that absolute path.

```
# validate (DSL or JSON; -workspace is required)
java -jar structurizr.war validate -workspace workspace.dsl
docker run -it --rm -v $PWD:/usr/local/structurizr structurizr/structurizr validate -workspace /usr/local/structurizr/workspace.dsl

# inspect: prints recommendations/violations; exit code = number of violations shown
java -jar structurizr.war inspect -workspace workspace.dsl [-severity error,warning,info,ignore]

# export: one output file per view, written to -output (default: next to the workspace file)
java -jar structurizr.war export -workspace workspace.dsl -format <fmt> [-output diagrams]
#   -format: png | svg | json | mermaid | plantuml (= plantuml/structurizr) | plantuml/c4plantuml
#            | websequencediagrams (dynamic views only) | static | theme | <fully.qualified.ExporterClass>
#   png/svg extras: -mode light|dark (default light)   -animation true|false (default false)
#   png/svg from a running instance instead of a file: -url http://localhost:8080/workspace/1/diagrams

# PNG/SVG need the Playwright build
java -jar structurizr-<ver>-playwright.war export -workspace workspace.dsl -format png -output diagrams
docker run -it --rm -v $PWD:/usr/local/structurizr structurizr/structurizr:<ver>-playwright \
  export -workspace /usr/local/structurizr/workspace.dsl -format svg -output /usr/local/structurizr/diagrams

# local: interactive viewer/editor at http://localhost:8080 (localhost only; no auth)
java -jar structurizr.war local <data-directory>            # change port with -Dserver.port=NNNN
docker run -it --rm -p 8080:8080 -v $PWD:/usr/local/structurizr structurizr/structurizr local   # PORT env var
```

Notes:
- PNG/SVG export drives headless Chromium via Playwright; **Chromium is downloaded on first run** (slow, needs
  network). Use the `-playwright` war or Docker tag (the png-and-svg docs page still refers to the older
  `structurizr-preview.war`; that also works).
- PNG/SVG export **goes via the static-site export**: the DSL is rendered with `autoLayout`; if you have
  arranged diagrams by hand in `local`, export the JSON (`workspace.json`, which holds layout) instead of the DSL.
  Documentation and decisions are stripped from static-site/image exports.
- Output naming: "files will be created one per view", named from the view key (plus `-dark` / animation-step
  suffixes when those options are on). Exact prefix varies by exporter; check the output directory.
- `local` looks for `workspace.dsl` then `workspace.json` in the data directory; edits to the DSL show on
  browser refresh; layout changes are auto-saved (every 5000 ms) to `workspace.json`.
- Mermaid/PlantUML exports ignore most element/relationship styling and themes; only the Structurizr renderer
  (png/svg/static/local) honours them fully.

## 2. Minimal workspace skeleton

```structurizr
workspace "Name" "Description" {

    !identifiers hierarchical

    model {
        u  = person "User"
        s  = softwareSystem "System" {
            web = container "Web App" "Serves UI" "React"
            api = container "API" "Business logic" "Spring Boot"
            db  = container "Database" "Stores data" "PostgreSQL" "Database"
        }
        u -> s.web "Uses"
        s.web -> s.api "Calls" "JSON/HTTPS"
        s.api -> s.db "Reads from and writes to" "JDBC"
    }

    views {
        systemContext s "SystemContext" {
            include *
            autoLayout
        }
        container s "Containers" {
            include *
            autoLayout lr
        }
    }

    configuration {
        scope softwaresystem
    }
}
```

Syntax basics (dsl/basics):
- Imperative, **line by line, top to bottom; no forward references**. Define an element before you use its
  identifier. `model` comes before `views`.
- Keywords are case-insensitive (`autoLayout` == `autolayout`); identifiers, names and tags are case-sensitive.
- Tokens separated by whitespace; indentation irrelevant. Opening `{` on the same line, closing `}` on its own line.
- Double quotes are optional for single tokens, **required when a value contains whitespace**. Use `""` to skip an
  optional positional parameter (e.g. `container "Db" "" "PostgreSQL"`).
- Comments: `// ...`, `# ...`, `/* ... */` (single or multi-line). Continue a long line with a trailing `\`.
- `!const NAME value` / `!var NAME value`, referenced as `${NAME}` (environment variables work too).
- If the `views` block is missing or empty, a default System Landscape, System Context and Container view
  (with autoLayout) are generated. Always define views explicitly with stable keys instead.

## 3. Model elements

Syntax lines exactly as in the language reference. `[...]` optional, positional; `{ ... }` optional block.

| Keyword | Syntax | Default tags | Allowed inside |
|---|---|---|---|
| person | `person <name> [description] [tags] { ... }` | Element, Person | model, group |
| softwareSystem | `softwareSystem <name> [description] [tags] { ... }` | Element, Software System | model, group |
| container | `container <name> [description] [technology] [tags] { ... }` | Element, Container | softwareSystem, group |
| component | `component <name> [description] [technology] [tags] { ... }` | Element, Component | container, group |
| group | `group <name> { ... }` | (elements get `Group:<name>`) | model, softwareSystem, container, deploymentEnvironment, deploymentNode |
| element (custom) | `element <name> [metadata] [description] [tags] { ... }` | Element | model |
| deploymentEnvironment | `deploymentEnvironment <name> { ... }` | – | model |
| deploymentGroup | `deploymentGroup <name>` | – | deploymentEnvironment |
| deploymentNode | `deploymentNode <name> [description] [technology] [tags] [instances] { ... }` | Element, Deployment Node | deploymentEnvironment, deploymentNode, group |
| infrastructureNode | `infrastructureNode <name> [description] [technology] [tags] { ... }` | Element, Infrastructure Node | deploymentNode |
| softwareSystemInstance | `softwareSystemInstance <identifier> [deploymentGroups] [tags] { ... }` | + Software System Instance | deploymentNode |
| containerInstance | `containerInstance <identifier> [deploymentGroups] [tags] { ... }` | + Container Instance | deploymentNode |
| instanceOf | `instanceOf <identifier> [deploymentGroups] [tags] { ... }` | alias for the two above | deploymentNode |

Body keywords usable inside element blocks:

```
description "text"            technology "text"          url https://example.com
tags "A,B"   or   tags "A" "B"   or   tag "A"              # tags are additive to defaults
instances "4"    instances "1..N"                          # deploymentNode only; also 0..1, 1..3, 0..*, 1..*
properties {                                               # arbitrary name/value metadata, one pair per line
    owner "payments-team"
}
perspectives {
    "Security" "Handles PII; encrypted at rest"
}
group "Group name"                                         # alternative to wrapping in a group block
-> <identifier> [description] [technology] [tags]         # relationship from this element (see 4)
```

Identifiers (dsl/identifiers):
- `id = person "Name"`; identifiers are `[a-zA-Z0-9_]`; elements without an identifier cannot be referenced.
- **Default scope is flat**: every identifier must be unique across the whole workspace, so two containers both
  called `api` in different systems fail.
- `!identifiers hierarchical` (place before any elements, at the top of `model` or `workspace`) scopes identifiers
  to their parent; refer to children with dots: `system.api`, `system.api.controller`. Inside the parent block
  you still use the short name (`api -> db` inside the system). Applies to element identifiers only (not
  relationship or group identifiers).
- Names, separately, must be unique per scope: person/system names globally, container names within a system,
  component names within a container.
- Elements are referenced in views and relationships **by identifier, never by name**.

Groups: only elements of the same level in one group (people+systems at model level, containers in a system,
components in a container). Nest groups with `model { properties { "structurizr.groupSeparator" "/" } }`; style
with `element "Group"` or `element "Group:Company 1/Department 1"`.

Bulk/late edits: `!element <identifier> { tags "X" }`, `!elements "<expression>" { tag "X" }`,
`!relationship <identifier> { ... }`, `!relationships "<expression>" { ... }`. `!include <file|dir|url>` splices
another DSL fragment in place.

## 4. Relationships

```
<source id> -> <destination id> [description] [technology] [tags] { tags/url/properties/perspectives }
rel = a -> b "Description"                       # relationship identifier (flat, even in hierarchical mode)
softwareSystem "X" {
    -> other "Sends events to" "Kafka"           # source = enclosing element
    this -> other "Same thing, explicit"         # `this` = element in scope
}
```

- Default tag `Relationship`. Unidirectional; declare two for bidirectional.
- Permitted pairs: Person/SoftwareSystem/Container/Component -> any of Person/SoftwareSystem/Container/Component;
  DeploymentNode -> DeploymentNode; InfrastructureNode -> DeploymentNode/InfrastructureNode/instances;
  SoftwareSystemInstance/ContainerInstance -> InfrastructureNode. Custom `element` can relate to anything static.
- **Not permitted: parent to its own child** (system -> its container, container -> its component) or self.
- Multiple relationships between the same source and destination **must have different descriptions**.
- Relationships live in `model` (top level or inside element blocks), never in static views.
- `a -/> b` removes an (implied/replicated) relationship, used inside `deploymentEnvironment`.

Implied relationships (dsl/implied-relationships): enabled by default. Defining `user -> system.web` implies
`user -> system`; `sysA.api -> sysB.db` implies `sysA.api -> sysB`, `sysA -> sysB.db`, `sysA -> sysB`, each
**unless any relationship already exists** between that pair (strategy
`CreateImpliedRelationshipsUnlessAnyRelationshipExistsStrategy`). This is what makes `include *` in a System
Context view show arrows even though you only modelled container/component level. So: model relationships at
the lowest level you know (component or container), and let the higher levels be implied. Description and
technology are copied to the implied relationship. `!impliedRelationships false` (before the elements) turns it
off, after which you must declare system-level relationships yourself or context views will have no arrows.
`!impliedRelationships <fqcn>` plugs in a custom strategy.

## 5. Deployment modelling

```
deploymentEnvironment > deploymentNode (nested freely) > containerInstance | softwareSystemInstance | infrastructureNode
```

- `containerInstance <container id>`: places a container on the enclosing node. With hierarchical identifiers use
  the full path (`s.api`). Every relationship between two containers is **replicated automatically between all
  their instances** in the environment; use `deploymentGroup` to restrict replication to instances that share a
  group: `deploymentGroup "Region A"` then `containerInstance s.api "Region A"`.
- Relationships you write inside an environment are infrastructure-level: `lb -> s.web_inst`,
  `node1 -> node2 "Replicates to"`, `containerInstance -> infrastructureNode`. Give instances identifiers
  (`webInst = containerInstance s.web`) when you need to reference them.
- **Hierarchical identifiers apply inside deployment environments too** (verified with the CLI): an instance or
  infrastructure node defined in `prod > aws > s3` has the identifier `prod.aws.s3.webInst`. References resolve
  relative to the block you are in, so from inside `aws` write `cdn -> s3.webInst`; from the environment level or
  the model level write the path from there (`aws.cdn -> aws.s3.webInst` or `prod.aws.cdn -> prod.aws.s3.webInst`).
  A bare `webInst` outside its own node fails with `The destination element "webInst" does not exist`. Easiest
  habit: put each infrastructure relationship inside the deepest node that contains both ends.
- `instances "3"` on a deploymentNode draws an "x3" badge. `technology` on nodes is shown as metadata.
- Tag nodes with theme tags to get icons (see 7). The environment name is what deployment views reference.

Kubernetes example (verified theme tags are lower-case abbreviations: `Kubernetes - node|ns|deploy|sts|svc|ing|pod|cm|secret|pvc|job|cronjob|ds|hpa|pv|rs|sa`):

```structurizr
prod = deploymentEnvironment "Production" {
    deploymentNode "Kubernetes Cluster" "" "GKE 1.31" "Kubernetes - node" {
        deploymentNode "ingress-nginx" "" "Ingress" "Kubernetes - ing" {
            ingress = infrastructureNode "Ingress" "TLS termination, routing" "nginx" "Kubernetes - ing"
        }
        deploymentNode "shop" "" "Namespace" "Kubernetes - ns" {
            deploymentNode "web" "" "Deployment" "Kubernetes - deploy" {
                instances "2"
                webInst = containerInstance s.web
            }
            deploymentNode "api" "" "Deployment" "Kubernetes - deploy" {
                instances "3"
                apiInst = containerInstance s.api
            }
            deploymentNode "postgres" "" "StatefulSet" "Kubernetes - sts" {
                containerInstance s.db
            }
        }
    }
    ingress -> webInst "Forwards requests to" "HTTPS"
    ingress -> apiInst "Forwards /api to" "HTTPS"
}
```

AWS example (theme tag = `Amazon Web Services - <Service name>`; copy exact names from the theme JSON,
e.g. `RDS`, `Elastic Container Service`, `Elastic Load Balancing`, `Route 53`, `EC2 Instance`):

```structurizr
live = deploymentEnvironment "Live" {
    deploymentNode "Amazon Web Services" {
        deploymentNode "eu-west-1" "" "Region" {
            alb = infrastructureNode "Load Balancer" "" "" "Amazon Web Services - Elastic Load Balancing"
            deploymentNode "ECS Cluster" "" "Fargate" "Amazon Web Services - Elastic Container Service" {
                apiInst = containerInstance s.api
            }
            deploymentNode "Amazon RDS" "" "PostgreSQL 16" "Amazon Web Services - RDS" {
                containerInstance s.db
            }
        }
    }
    alb -> apiInst "Forwards requests to" "HTTPS"
}
```

## 6. Views

All views: `[key]` should be given explicitly (auto keys are "not guaranteed to be stable" and image files are
named after them); keys must be unique. Common body keywords: `include`, `exclude`, `autoLayout`, `default`,
`title "..."`, `description "..."`, `animation { ... }`, `properties { ... }`.

| View | Syntax | `include *` adds |
|---|---|---|
| systemLandscape | `systemLandscape [key] [description] { }` | all people and software systems |
| systemContext | `systemContext <system id> [key] [description] { }` | the system + directly connected people/systems |
| container | `container <system id> [key] [description] { }` | all containers of the system + directly connected people/systems |
| component | `component <container id> [key] [description] { }` | all components of the container + directly connected people, systems and containers of the same system |
| dynamic | `dynamic <*\|system id\|container id> [key] [description] { }` | n/a — you list relationship instances |
| deployment | `deployment <*\|system id> <environment id or name> [key] [description] { }` | `*`: all nodes, infra nodes and instances in the environment; system scope: all nodes + only that system's instances |
| filtered | `filtered <baseKey> <include\|exclude> <tags> [key] [description]` | n/a |
| custom | `custom [key] [title] [description] { }` | custom `element`s only |
| image | `image <*\|element id> [key] { plantuml\|mermaid\|kroki\|image <file\|url> }` | embeds an external picture |

Include / exclude:

```
include *                       # default set for the view type (see table)
include *?                      # "reluctant" wildcard: same elements, but only relationships to/from the scoped element(s)
include a b c                   # specific elements (must be permitted in this view type)
include "->s.api->"             # element plus incoming and outgoing neighbours ("->x" incoming only, "x->" outgoing only)
include "element.type==Container && element.parent==s"
include "element.tag==External"   include "element.tag!=Internal,Legacy"   include "element.technology==Kafka"
include "element.properties[owner]==payments"   include "element.group==Backend"
exclude thirdParty
exclude "* -> *"   exclude "s.api -> *"   exclude "* -> s.db"   exclude "s.web -> s.api"
exclude "relationship.tag==Async"   include "relationship.source==u"   include "relationship.destination==s"
```

Element types for `element.type==`: Person, SoftwareSystem, Container, Component, DeploymentNode,
InfrastructureNode, SoftwareSystemInstance, ContainerInstance, Custom. Combine expressions with `&&` / `||`;
quote any expression containing whitespace. Expressions are also accepted by `!elements` / `!relationships`.

Layout and misc:

```
autoLayout [tb|bt|lr|rl] [rankSeparation] [nodeSeparation]   # defaults: tb 300 300 (pixels)
default                                                       # this view opens first
title "Overridden title"
animation {                                                   # each line = one step (elements revealed)
    u
    s.web s.api
    s.db
}
```

Dynamic views show **ordered instances of relationships that already exist in the model** (a relationship
`a -> b` must be declared in `model`; the description in the view may differ and be more specific; a step in
the reverse direction of an existing relationship is rendered as a response). Scope `*` permits people and
systems, a system scope adds its containers, a container scope adds its components.

```structurizr
dynamic s.api "Checkout" "How an order is placed" {
    title "Place order"
    u -> s.web "Submits order"                          # auto-numbered 1, 2, 3 ...
    s.web -> s.api "POST /orders" "JSON/HTTPS"
    {                                                  # parallel block: children get the same number
        {
            s.api -> s.db "Inserts order"
        }
        {
            s.api -> queue "Publishes OrderPlaced"
        }
    }
    s.api -> s.web "Returns 201"
    autoLayout lr
}
dynamic * "Explicit" {
    1: a -> b "Requests"        # explicit ordering; equal numbers = concurrent
    2: b -> c "Reads"
    2: b -> d "Reads"
    3: b -> e "Sends"
    autoLayout
}
```

Filtered views: `filtered "Containers" include "Element,Relationship" "Containers-All"` and
`filtered "Containers" exclude "Legacy" "Containers-NoLegacy"`. Base must be a landscape/context/container/
component view. Once any filtered view exists on a base view, the base view itself is no longer listed, so add
an "include Element,Relationship" filter if you still want it.

## 7. Styles and themes

Styles match on **tags**, cascading like CSS in declaration order (later/more specific tag wins). Defaults
(server/diagrams/notation): elements 450x300 px grey boxes, text #000000, font 24, solid 2 px border, opacity 100;
relationships 2 px dashed grey, routing Direct, label width 200, position 50.

```
styles {
    element <tag> {
        shape <Box|RoundedBox|Circle|Ellipse|Hexagon|Diamond|Cylinder|Bucket|Pipe|Person|Robot|Folder|WebBrowser|Window|Terminal|Shell|MobileDevicePortrait|MobileDeviceLandscape|Component>
        icon <file|url>            width <int>          height <int>
        background <#rrggbb|name>  color <#rrggbb|name> (or colour)   stroke <#rrggbb|name>   strokeWidth <1-10>
        fontSize <int>             border <solid|dashed|dotted>       opacity <0-100>
        metadata <true|false>      description <true|false>           properties { name value }
    }
    relationship <tag> {
        thickness <int>            color <#rrggbb|name> (or colour)   style <solid|dashed|dotted>
        routing <Direct|Orthogonal|Curved>   jump <true|false>        fontSize <int>
        width <int>                position <0-100>                   opacity <0-100>     properties { name value }
    }
    light { ... }   # element/relationship styles used in light mode only
    dark  { ... }   # element/relationship styles used in dark mode only
}
theme  <name|url|file>
themes <name|url|file> [name|url|file] ...
terminology { person "Actor"  softwareSystem "System"  container "Service"  component "Module"
              deploymentNode "Node"  infrastructureNode "Infra"  relationship "Uses"
              metadata <square|round|curly|angle|double-angle|none> }
```

Recommended default block (conventional C4 colours; tags `Database`, `Queue`, `External`, `Browser`, `Mobile`
are ones you add yourself in the model):

```structurizr
styles {
    element "Element" {
        color #ffffff
        fontSize 22
    }
    element "Person" {
        shape person
        background #08427b
    }
    element "Software System" {
        shape roundedbox
        background #1168bd
    }
    element "Container" {
        background #438dd5
    }
    element "Component" {
        shape component
        background #85bbf0
        color #000000
    }
    element "Database" {
        shape cylinder
    }
    element "Queue" {
        shape pipe
    }
    element "Browser" {
        shape webbrowser
    }
    element "Mobile" {
        shape mobiledeviceportrait
    }
    element "External" {
        background #999999
    }
    element "Deployment Node" {
        color #000000
    }
    relationship "Relationship" {
        routing orthogonal
    }
    relationship "Async" {
        style dashed
    }
    dark {
        element "Component" {
            color #ffffff
        }
    }
}
```

Built-in themes (verified URLs; tag elements with the exact style names from the theme, e.g.
`"Amazon Web Services - Lambda"`, `"Microsoft Azure - Azure Active Directory"`,
`"Google Cloud Platform - Cloud Run"`, `"Kubernetes - pod"`, `"Oracle Cloud Infrastructure - Autonomous Database"`).
Themes only supply icon/colour; combine with your own `styles` for shapes. Prefer URLs: names such as
`theme microsoft-azure-2021.01` work only when the theme is installed on the tool/server.

```
themes https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json
themes https://static.structurizr.com/themes/microsoft-azure-2023.01.24/theme.json
themes https://static.structurizr.com/themes/google-cloud-platform-v1.5/theme.json
themes https://static.structurizr.com/themes/kubernetes-v0.3/theme.json
themes https://static.structurizr.com/themes/oracle-cloud-infrastructure-2023.04.01/theme.json
```


## 8. Documentation and ADRs

```
!docs <path> [fullyQualifiedClassName]     # Markdown/AsciiDoc files; path relative to the DSL file
!adrs <path> [type|fqn]                    # ADRs (e.g. adr-tools Markdown format)
```

Allowed inside `workspace`, `softwareSystem` and `container`, attaching docs to that scope, e.g.
`!docs docs` and `!adrs adrs` right after `!identifiers hierarchical`, or inside a container block for
container-level docs. Stripped from static/image exports; visible in `local` and on the server.

## 9. Validation rules and common errors

- **Identifiers defined before use** (no forward references); an undefined identifier is the most common error.
  Relationships/views that reference an element must come after it in file order.
- **Unique identifiers**: flat scope by default; enable `!identifiers hierarchical` before defining elements if
  names repeat across parents, then use dotted paths from outside the parent - this includes container
  instances and infrastructure nodes inside deployment nodes (`aws.s3.webInst` from the environment level,
  `s3.webInst` from inside `aws`; see 5). `The source/destination element "x" does not exist` almost always
  means a scoped identifier was used from the wrong block.
- **Line-based grammar**: one statement per line; `{` must end the line that opens a block and `}` must be on
  its own line; there is no `;` separator (`include *; autoLayout` on one line is a parse error that surfaces
  as "Unexpected end of DSL content - are one or more closing curly braces missing?").
- **Remote themes need network**: `themes https://static.structurizr.com/...` makes `validate`/`export` fetch
  the URL; in an offline or proxied environment that fails with `HTTP status=403`/timeouts even though the DSL
  is fine. Use themes only when the renderer has internet access, otherwise rely on local `styles`.
- **Unique names per scope**: people/systems globally; containers per system; components per container.
- **Unique view keys**; give every view a key and use it as the image filename.
- **Relationship uniqueness**: same source+destination must have distinct descriptions.
- **Permitted relationship pairs** only (see 4); never parent -> own child, never self; deployment elements only
  relate to deployment elements; instances are created via `containerInstance`, not `->`.
- **Nesting**: containers only inside softwareSystem; components only inside container; deploymentNode only inside
  deploymentEnvironment/deploymentNode; groups only contain elements of one level.
- **Views only reference permitted element types**: a component view of container X can include X's components,
  people, systems and containers of X's system — not components of another container. A dynamic view step
  requires the relationship to exist in the model.
- `include *` in a component view of a container with **no components yields an empty diagram**; only create
  component views for containers you have actually decomposed.
- **Quotes**: any name/description/tag/expression containing spaces must be double-quoted; unquoted multi-word
  text is parsed as several positional parameters. Empty optional positions need `""`.
- **Case**: keywords case-insensitive; tags, identifiers, names, style tags case-sensitive (`"Software System"`,
  `"Database"`).
- **Positional order matters**: `container <name> [description] [technology] [tags]` — technology is third, so
  `container "API" "Spring Boot"` puts "Spring Boot" in the description.
- **Comments**: `//`, `#`, `/* */`; a `#` inside a quoted string is fine.
- **Layout**: every view needs `autoLayout` for image/mermaid/plantuml export from DSL (no manual coordinates in
  DSL); manual layout only survives in `workspace.json`.
- **Scope**: `configuration { scope softwaresystem }` makes validation require exactly one system with
  containers (or docs); with `landscape` scope containers are rejected. Recommendation: one software system per
  workspace; external systems appear as plain `softwareSystem` without containers.
- **Implied relationships** appear in context/container views automatically; if a context view has no arrows,
  either `!impliedRelationships false` is set or the lower-level relationship was never declared.
- Run `validate` first, then `inspect` (recommendations such as missing descriptions/technology), then `export`.

## 10. Complete example workspace

```structurizr
workspace "Shop" "Online shop backend and web front end" {

    !identifiers hierarchical
    // !docs docs        (uncomment once the directories exist)
    // !adrs adrs

    model {
        customer = person "Customer" "Buys products through the web shop."

        payments = softwareSystem "Payment Provider" "Card processing (Stripe)." "External"
        email    = softwareSystem "Email Service" "Transactional email (SendGrid)." "External"

        shop = softwareSystem "Shop" "Sells products online." {
            spa    = container "Web SPA" "Storefront UI" "React 18, TypeScript" "Browser"
            api    = container "API" "REST API and business rules" "Java 21, Spring Boot 3" {
                orders    = component "Order Controller" "REST endpoints for orders" "Spring MVC"
                catalog   = component "Catalog Service" "Product lookup and pricing" "Spring Service"
                orderSvc  = component "Order Service" "Order lifecycle" "Spring Service"
                paySvc    = component "Payment Gateway" "Talks to the payment provider" "Spring, WebClient"
                repo      = component "Order Repository" "Persistence for orders" "Spring Data JPA"
                publisher = component "Event Publisher" "Publishes domain events" "Spring AMQP"
            }
            worker = container "Notification Worker" "Consumes events, sends email" "Java 21, Spring Boot 3"
            db     = container "Database" "Orders, products, users" "PostgreSQL 16" "Database"
            cache  = container "Cache" "Sessions and product cache" "Redis 7" "Database"
            queue  = container "Message Broker" "Domain events" "RabbitMQ" "Queue"
        }

        // relationships at the lowest known level; higher levels are implied
        customer -> shop.spa "Browses and orders using" "HTTPS"
        shop.spa -> shop.api.orders "Calls" "JSON/HTTPS"
        shop.api.orders    -> shop.api.orderSvc "Delegates to"
        shop.api.orders    -> shop.api.catalog  "Reads products via"
        shop.api.orderSvc  -> shop.api.repo     "Persists orders with"
        shop.api.orderSvc  -> shop.api.paySvc   "Charges cards via"
        shop.api.orderSvc  -> shop.api.publisher "Emits OrderPlaced via"
        shop.api.catalog   -> shop.cache        "Caches products in" "Redis protocol"
        shop.api.repo      -> shop.db           "Reads from and writes to" "JDBC"
        shop.api.paySvc    -> payments          "Creates charges using" "HTTPS"
        shop.api.publisher -> shop.queue        "Publishes to" "AMQP" "Async"
        shop.worker        -> shop.queue        "Consumes from" "AMQP" "Async"
        shop.worker        -> email             "Sends order confirmations using" "HTTPS"
        shop.worker        -> shop.db           "Reads order details from" "JDBC"

        prod = deploymentEnvironment "Production" {
            deploymentNode "Kubernetes Cluster" "" "EKS 1.31" "Kubernetes - node" {
                ingress = infrastructureNode "Ingress" "Routes external traffic" "nginx ingress" "Kubernetes - ing"
                deploymentNode "shop" "" "Namespace" "Kubernetes - ns" {
                    deploymentNode "spa" "" "Deployment" "Kubernetes - deploy" {
                        instances "2"
                        spaInst = containerInstance shop.spa
                    }
                    deploymentNode "api" "" "Deployment" "Kubernetes - deploy" {
                        instances "3"
                        apiInst = containerInstance shop.api
                    }
                    deploymentNode "worker" "" "Deployment" "Kubernetes - deploy" {
                        containerInstance shop.worker
                    }
                    deploymentNode "rabbitmq" "" "StatefulSet" "Kubernetes - sts" {
                        containerInstance shop.queue
                    }
                }
            }
            deploymentNode "Amazon RDS" "" "PostgreSQL 16, Multi-AZ" "Amazon Web Services - RDS" {
                containerInstance shop.db
            }
            ingress -> spaInst "Forwards / to" "HTTPS"
            ingress -> apiInst "Forwards /api to" "HTTPS"
        }
    }

    views {
        systemContext shop "SystemContext" "People and systems around the shop" {
            include *
            autoLayout
            default
        }
        container shop "Containers" "Deployable units of the shop" {
            include *
            autoLayout lr
        }
        component shop.api "ApiComponents" "Inside the API container" {
            include *
            autoLayout lr
        }
        deployment shop prod "ProductionDeployment" {
            include *
            autoLayout lr
        }
        dynamic shop.api "PlaceOrder" "Customer places an order" {
            title "Place order"
            customer -> shop.spa "Submits checkout form"
            shop.spa -> shop.api.orders "POST /orders" "JSON/HTTPS"
            shop.api.orders -> shop.api.orderSvc "placeOrder()"
            shop.api.orderSvc -> shop.api.paySvc "charge()"
            shop.api.paySvc -> payments "Create charge" "HTTPS"
            {
                {
                    shop.api.orderSvc -> shop.api.repo "save()"
                }
                {
                    shop.api.orderSvc -> shop.api.publisher "publish(OrderPlaced)"
                }
            }
            shop.api.publisher -> shop.queue "OrderPlaced" "AMQP"
            autoLayout lr
        }

        styles {
            element "Person" {
                shape person
                background #08427b
                color #ffffff
            }
            element "Software System" {
                background #1168bd
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Component" {
                background #85bbf0
            }
            element "Database" {
                shape cylinder
            }
            element "Queue" {
                shape pipe
            }
            element "Browser" {
                shape webbrowser
            }
            element "External" {
                background #999999
            }
        }
        themes https://static.structurizr.com/themes/kubernetes-v0.3/theme.json https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json
    }

    configuration {
        scope softwaresystem
    }
}
```

Export it: `java -jar structurizr-<ver>-playwright.war export -workspace workspace.dsl -format png -output diagrams`
produces one image per key: SystemContext, Containers, ApiComponents, ProductionDeployment, PlaceOrder.
