// Template for a single-software-system C4 workspace. Replace names, add containers/components,
// keep the view keys stable. Structurizr DSL is line-based: '{' ends a line, '}' stands alone.
workspace "SYSTEM_NAME" "One sentence: what this system is for and who it serves." {

    !identifiers hierarchical

    model {
        // ---- people --------------------------------------------------------
        user = person "End User" "Uses the product through the web app."

        // ---- external systems (things this codebase talks to but does not own)
        // idp = softwareSystem "Identity Provider" "SSO / OAuth2" "External"

        // ---- the system being modelled ------------------------------------
        system = softwareSystem "SYSTEM_NAME" "Responsibility in one line." {
            web = container "Web App" "Single-page UI." "React 18 / TypeScript" "Browser"
            api = container "API" "Serves the UI and integrations." "FastAPI / Python 3.12" {
                // components = major internal building blocks, each mapped to a package/dir
                // routes   = component "HTTP Routes"  "Request parsing, auth, validation" "FastAPI routers"
                // domain   = component "Domain Model" "Business rules for X"              "Python package app/domain"
                // repo     = component "Repositories" "Persistence for aggregates"        "SQLAlchemy"
            }
            db = container "Database" "Stores accounts, orders, ..." "PostgreSQL 16" "Database"
            // queue  = container "Event Bus" "Async integration between services" "Kafka" "Queue"
            // worker = container "Worker" "Background jobs" "Celery"
        }

        // ---- relationships: verb phrase + technology, direction = initiator -> target
        user -> system.web "Uses" "HTTPS"
        system.web -> system.api "Calls" "JSON/HTTPS"
        system.api -> system.db "Reads from and writes to" "SQL/psycopg"
        // system.api -> idp "Validates tokens with" "OIDC"

        // ---- deployment (only if infra definitions exist in the repo) -------
        // prod = deploymentEnvironment "Production" {
        //     deploymentNode "AWS eu-central-1" "" "Amazon Web Services" {
        //         deploymentNode "EKS cluster" "" "Kubernetes 1.30" {
        //             deploymentNode "api pod" "" "Deployment, 3 replicas" "" 3 {
        //                 containerInstance system.api
        //             }
        //         }
        //         deploymentNode "RDS" "" "PostgreSQL 16" {
        //             containerInstance system.db
        //         }
        //     }
        // }
    }

    views {
        systemContext system "SystemContext" "Who uses the system and what it depends on." {
            include *
            autoLayout lr
        }

        container system "Containers" "Deployable units and how they communicate." {
            include *
            autoLayout lr
        }

        // component system.api "Components-Api" "Internal structure of the API." {
        //     include *
        //     autoLayout tb
        // }

        // deployment system "Production" "Deployment-Production" "Where containers run in production." {
        //     include *
        //     autoLayout lr
        // }

        // dynamic system "Dynamic-KeyFlow" "What happens when a user does X." {
        //     user -> system.web "Submits form"
        //     system.web -> system.api "POST /things"
        //     system.api -> system.db "INSERT thing"
        //     autoLayout lr
        // }

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
                color #000000
            }
            element "External" {
                background #999999
                color #ffffff
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
            element "Unverified" {
                border dashed
                stroke #d97706
            }
        }
    }
}
