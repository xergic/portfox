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

    // Infrastructure
    case postgres
    case mysql
    case mongodb
    case redis
    case meilisearch
    case elasticsearch
    case minio
    case mailpit
    case rabbitmq

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
        case .postgres: "PostgreSQL"
        case .mysql: "MySQL"
        case .mongodb: "MongoDB"
        case .redis: "Redis"
        case .meilisearch: "Meilisearch"
        case .elasticsearch: "Elasticsearch"
        case .minio: "MinIO"
        case .mailpit: "Mailpit"
        case .rabbitmq: "RabbitMQ"
        case .unknown: "Local Process"
        }
    }

    public var category: ServiceCategory {
        switch self {
        case .vite, .nextJS, .nuxt, .astro, .svelteKit, .remix, .angular, .storybook:
            .web
        case .nestJS, .fastAPI, .django, .flask, .uvicorn, .wrangler:
            .api
        case .expo, .metro:
            .tooling
        case .node, .bun, .deno, .python:
            .api
        case .postgres, .mysql, .mongodb, .redis, .elasticsearch, .meilisearch:
            .database
        case .minio, .mailpit, .rabbitmq:
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
        case .postgres: [5432]
        case .mysql: [3306]
        case .mongodb: [27017]
        case .redis: [6379]
        case .meilisearch: [7700]
        case .elasticsearch: [9200]
        case .minio: [9001, 9000]
        case .mailpit: [8025, 1025]
        case .rabbitmq: [15672, 5672]
        case .unknown: []
        }
    }

    /// True when opening `http://host:port` in a browser is meaningful.
    public var isHTTP: Bool {
        switch category {
        case .web, .api, .tooling: true
        case .database, .infrastructure, .unknown: false
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
        case .node, .bun, .deno, .python: 1
        case .uvicorn, .metro: 2
        default: 3
        }
    }
}
