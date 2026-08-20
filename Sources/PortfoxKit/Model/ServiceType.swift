import Foundation

/// Broad family a service belongs to. Drives grouping and the future filter chips.
public enum ServiceCategory: String, Codable, Sendable, CaseIterable {
    case web
    case api
    case database
    case infrastructure
    case tooling
    case unknown
}

/// Every service Portfox can identify. Adding a case here plus one `DetectorCatalog`
/// entry plus one asset is the whole cost of supporting a new framework.
public enum ServiceType: String, CaseIterable, Codable, Sendable {
    // Node ecosystem
    case vite
    case nextJS
    case nuxt
    case astro
    case svelteKit
    case remix
    case angular
    case nestJS
    case storybook
    case expo
    case metro
    case node
    case bun
    case deno

    // Cloudflare
    case wrangler

    // Python
    case fastAPI
    case django
    case flask
    case uvicorn
    case python
    case gunicorn
    case streamlit
    case jupyter
    case flower

    // JVM
    case springBoot
    case quarkus
    case micronaut
    case tomcat
    case ktor
    case java

    // .NET
    case aspNet
    case dotnet

    // Ruby
    case rails
    case puma
    case sinatra
    case ruby

    // PHP
    case laravel
    case symfony
    case php

    // Compiled
    case go
    case rust

    // Infrastructure
    case postgres
    case mysql
    case mongodb
    case redis
    case meilisearch
    case elasticsearch
    case minio
    case mailpit
    case mailhog
    case rabbitmq
    case kafka
    case nats
    case memcached
    case valkey
    case clickhouse
    case typesense
    case qdrant
    case temporal
    case docker

    // Proxies and local tooling
    case nginx
    case caddy
    case ngrok
    case grafana
    case prometheus
    case ollama
    case pocketbase
    case prismaStudio

    case unknown

    public var displayName: String {
        switch self {
        case .vite: "Vite"
        case .nextJS: "Next.js"
        case .nuxt: "Nuxt"
        case .astro: "Astro"
        case .svelteKit: "SvelteKit"
        case .remix: "React Router"
        case .angular: "Angular"
        case .nestJS: "NestJS"
        case .storybook: "Storybook"
        case .expo: "Expo"
        case .metro: "Metro"
        case .node: "Node.js"
        case .bun: "Bun"
        case .deno: "Deno"
        case .wrangler: "Cloudflare Workers"
        case .fastAPI: "FastAPI"
        case .django: "Django"
        case .flask: "Flask"
        case .uvicorn: "Uvicorn"
        case .python: "Python"
        case .springBoot: "Spring Boot"
        case .quarkus: "Quarkus"
        case .micronaut: "Micronaut"
        case .tomcat: "Tomcat"
        case .ktor: "Ktor"
        case .java: "Java"
        case .aspNet: "ASP.NET Core"
        case .dotnet: ".NET"
        case .rails: "Ruby on Rails"
        case .puma: "Puma"
        case .sinatra: "Sinatra"
        case .ruby: "Ruby"
        case .laravel: "Laravel"
        case .symfony: "Symfony"
        case .php: "PHP"
        case .go: "Go"
        case .rust: "Rust"
        case .gunicorn: "Gunicorn"
        case .streamlit: "Streamlit"
        case .jupyter: "Jupyter"
        case .flower: "Flower"
        case .postgres: "PostgreSQL"
        case .mysql: "MySQL"
        case .mongodb: "MongoDB"
        case .redis: "Redis"
        case .meilisearch: "Meilisearch"
        case .elasticsearch: "Elasticsearch"
        case .minio: "MinIO"
        case .mailpit: "Mailpit"
        case .rabbitmq: "RabbitMQ"
        case .mailhog: "MailHog"
        case .kafka: "Kafka"
        case .nats: "NATS"
        case .memcached: "Memcached"
        case .valkey: "Valkey"
        case .clickhouse: "ClickHouse"
        case .typesense: "Typesense"
        case .qdrant: "Qdrant"
        case .temporal: "Temporal"
        case .docker: "Docker"
        case .nginx: "nginx"
        case .caddy: "Caddy"
        case .ngrok: "ngrok"
        case .grafana: "Grafana"
        case .prometheus: "Prometheus"
        case .ollama: "Ollama"
        case .pocketbase: "PocketBase"
        case .prismaStudio: "Prisma Studio"
        case .unknown: "Local Process"
        }
    }

    public var category: ServiceCategory {
        switch self {
        case .vite, .nextJS, .nuxt, .astro, .svelteKit, .remix, .angular, .storybook,
             .tomcat, .rails, .laravel, .symfony, .streamlit, .nginx, .caddy:
            .web
        case .nestJS, .fastAPI, .django, .flask, .uvicorn, .wrangler,
             .node, .bun, .deno, .python,
             .springBoot, .quarkus, .micronaut, .ktor, .java,
             .aspNet, .dotnet, .puma, .sinatra, .ruby, .php, .go, .rust, .gunicorn,
             .ollama, .pocketbase:
            .api
        case .expo, .metro, .jupyter, .flower, .ngrok, .grafana, .prometheus, .prismaStudio:
            .tooling
        case .postgres, .mysql, .mongodb, .redis, .elasticsearch, .meilisearch,
             .memcached, .valkey, .clickhouse, .typesense, .qdrant:
            .database
        case .minio, .mailpit, .mailhog, .rabbitmq, .kafka, .nats, .temporal, .docker:
            .infrastructure
        case .unknown:
            .unknown
        }
    }

    /// Ports the service conventionally binds, most useful first. Order matters:
    /// when a service holds several of its own default ports, the first one wins
    /// the port pill. Mailpit binds 8025 for its web UI and 1025 for SMTP, and
    /// the web UI is what a user wants to open.
    public var defaultPorts: [Int] {
        switch self {
        case .vite: [5173, 4173]
        case .nextJS: [3000]
        case .nuxt: [3000]
        case .astro: [4321]
        case .svelteKit: [5173]
        case .remix: [5173, 3000]
        case .angular: [4200]
        case .nestJS: [3000]
        case .storybook: [6006]
        case .expo: [8081, 19000]
        case .metro: [8081]
        case .node: [3000, 4000, 8000, 8080]
        case .bun: [3000]
        case .deno: [8000]
        case .wrangler: [8787]
        case .fastAPI, .uvicorn: [8000]
        case .django: [8000]
        case .flask: [5000]
        case .python: [8000]
        case .springBoot, .quarkus, .micronaut, .ktor: [8080]
        case .tomcat: [8080, 8443]
        case .java: [8080, 8000]
        case .aspNet, .dotnet: [5000, 5001]
        case .rails: [3000]
        case .puma: [9292, 3000]
        case .sinatra: [4567]
        case .ruby: [3000, 4567, 9292]
        case .laravel: [8000]
        case .symfony: [8000, 8001]
        case .php: [8000, 8080]
        case .go: [8080, 3000]
        case .rust: [8000, 3000]
        case .gunicorn: [8000]
        case .streamlit: [8501]
        case .jupyter: [8888, 8889]
        case .flower: [5555]
        case .postgres: [5432]
        case .mysql: [3306]
        case .mongodb: [27017]
        case .redis: [6379]
        case .meilisearch: [7700]
        case .elasticsearch: [9200]
        case .minio: [9001, 9000]
        case .mailpit: [8025, 1025]
        case .rabbitmq: [15672, 5672]
        case .mailhog: [8025, 1025]
        case .kafka: [9092, 9094]
        case .nats: [8222, 4222]
        case .memcached: [11211]
        case .valkey: [6379]
        // 8123 first: the HTTP interface is the one a browser can open, and it
        // keeps the port pill off the native protocol on 9000.
        case .clickhouse: [8123, 9000]
        case .typesense: [8108]
        case .qdrant: [6333, 6334]
        case .temporal: [8233, 7233]
        // A container publishes whatever it likes. There is no default to claim.
        case .docker: []
        case .nginx: [80, 8080]
        case .caddy: [80, 443, 2019]
        case .ngrok: [4040]
        case .grafana: [3000]
        case .prometheus: [9090]
        case .ollama: [11434]
        case .pocketbase: [8090]
        case .prismaStudio: [5555]
        case .unknown: []
        }
    }

    /// Infrastructure and databases that nonetheless serve a browsable UI or a
    /// plain HTTP API on their first default port. Without this Mailpit's inbox
    /// on 8025 had no Open button, purely because its category said otherwise.
    private static let webInterfaces: Set<ServiceType> = [
        .mailpit, .mailhog, .minio, .rabbitmq, .temporal,
        .elasticsearch, .meilisearch, .clickhouse, .qdrant
    ]

    /// True when opening `http://host:port` in a browser is meaningful.
    public var isHTTP: Bool {
        switch category {
        case .web, .api, .tooling: true
        case .database, .infrastructure: Self.webInterfaces.contains(self)
        case .unknown: false
        }
    }

    /// Asset-catalogue image name for the framework badge.
    public var iconAssetName: String { "service-\(rawValue)" }

    /// SF Symbol shown when the bundled asset is missing.
    public var fallbackSymbol: String {
        switch category {
        case .web: "globe"
        case .api: "server.rack"
        case .database: "cylinder.split.1x2"
        case .infrastructure: "shippingbox"
        case .tooling: "hammer"
        case .unknown: "questionmark.app.dashed"
        }
    }

    /// Higher wins when two detectors tie on score, so Next.js beats generic Node.
    public var specificity: Int {
        switch self {
        case .unknown: 0
        // Generic runtimes. Any framework running on top of one must outrank it.
        case .node, .bun, .deno, .python, .java, .dotnet, .ruby, .php, .go, .rust: 1
        // Application servers. More specific than a bare runtime, less specific
        // than the framework they are serving.
        case .uvicorn, .metro, .gunicorn, .puma, .tomcat: 2
        default: 3
        }
    }
}
