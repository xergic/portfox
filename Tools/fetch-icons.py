#!/usr/bin/env python3
"""Fetch framework logos from simple-icons into the app asset catalogue.

Icon paths are CC0. The trademarks remain the property of their owners, and are
used here only to identify the software each service is running.

Run from the repository root:  python3 Tools/fetch-icons.py
"""
import copy
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

RAW = "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/{}.svg"
DATA = "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/data/simple-icons.json"

# ServiceType.rawValue -> (simple-icons slug, simple-icons title)
ICONS = {
    "vite": ("vite", "Vite"),
    "nextJS": ("nextdotjs", "Next.js"),
    "nuxt": ("nuxt", "Nuxt"),
    "astro": ("astro", "Astro"),
    "svelteKit": ("svelte", "Svelte"),
    "remix": ("reactrouter", "React Router"),
    "angular": ("angular", "Angular"),
    "nestJS": ("nestjs", "NestJS"),
    "storybook": ("storybook", "Storybook"),
    "expo": ("expo", "Expo"),
    "metro": ("react", "React"),
    "node": ("nodedotjs", "Node.js"),
    "bun": ("bun", "Bun"),
    "deno": ("deno", "Deno"),
    "wrangler": ("cloudflareworkers", "Cloudflare Workers"),
    "fastAPI": ("fastapi", "FastAPI"),
    "django": ("django", "Django"),
    "flask": ("flask", "Flask"),
    "uvicorn": ("gunicorn", "Gunicorn"),
    "python": ("python", "Python"),
    "postgres": ("postgresql", "PostgreSQL"),
    "mysql": ("mysql", "MySQL"),
    "mongodb": ("mongodb", "MongoDB"),
    "redis": ("redis", "Redis"),
    "meilisearch": ("meilisearch", "Meilisearch"),
    "elasticsearch": ("elasticsearch", "Elasticsearch"),
    "minio": ("minio", "MinIO"),
    "rabbitmq": ("rabbitmq", "RabbitMQ"),
    "springBoot": ("springboot", "Spring Boot"),
    "quarkus": ("quarkus", "Quarkus"),
    "tomcat": ("apachetomcat", "Apache Tomcat"),
    "ktor": ("ktor", "Ktor"),
    # simple-icons carries no Java mark, for trademark reasons.
    "java": ("openjdk", "OpenJDK"),
    "dotnet": ("dotnet", ".NET"),
    "aspNet": ("dotnet", ".NET"),
    "ruby": ("ruby", "Ruby"),
    "rails": ("rubyonrails", "Ruby on Rails"),
    "php": ("php", "PHP"),
    "laravel": ("laravel", "Laravel"),
    "symfony": ("symfony", "Symfony"),
    "go": ("go", "Go"),
    "rust": ("rust", "Rust"),
    "gunicorn": ("gunicorn", "Gunicorn"),
    "streamlit": ("streamlit", "Streamlit"),
    "jupyter": ("jupyter", "Jupyter"),
    "kafka": ("apachekafka", "Apache Kafka"),
    "clickhouse": ("clickhouse", "ClickHouse"),
    "qdrant": ("qdrant", "Qdrant"),
    "nats": ("natsdotio", "NATS.io"),
    "nginx": ("nginx", "nginx"),
    "caddy": ("caddy", "Caddy"),
    "docker": ("docker", "Docker"),
    "ngrok": ("ngrok", "ngrok"),
    "grafana": ("grafana", "Grafana"),
    "prometheus": ("prometheus", "Prometheus"),
    "ollama": ("ollama", "Ollama"),
    "pocketbase": ("pocketbase", "PocketBase"),
    "temporal": ("temporal", "Temporal"),
    "prismaStudio": ("prisma", "Prisma"),
}

# Types with no usable brand mark. They render `ServiceType.fallbackSymbol`.
# The reason matters: without it somebody eventually "fixes" one of these by
# guessing a slug, and two of the guesses below are actively wrong.
NO_BRAND_ICON = {
    "unknown": "renders the SF Symbol fallback by design",
    "mailpit": "no simple-icons entry",
    "mailhog": "no simple-icons entry",
    "micronaut": "no simple-icons entry",
    "valkey": "no simple-icons entry",
    "memcached": "no simple-icons entry",
    "typesense": "no simple-icons entry",
    "sinatra": "no simple-icons entry",
    "puma": "the simple-icons `puma` slug is the shoe brand, not the Ruby server",
    "flower": "the simple-icons `flower` slug is flower.ai, not Celery Flower",
    "uvicorn": "gives up the Gunicorn mark it borrowed, now that gunicorn is a real type",
}

# The popover is always dark, so a near-black brand colour would be invisible.
# Those render white, which is how the vendors themselves present these marks on
# a dark background. HSL lightness rather than relative luminance, because
# luminance under-rates saturated brand colours such as Angular red.
LIGHTNESS_FLOOR = 0.25

DESTINATION = pathlib.Path("App/Portfox/Resources/Assets.xcassets/Services")

CONTENTS = {
    "images": [{"filename": "", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"preserves-vector-representation": True, "template-rendering-intent": "original"},
}


def normalise(title: str) -> str:
    """simple-icons' own slug rule. A dot becomes the word, so ".NET" is
    "dotnet" and "NATS.io" is "natsio" only if you forget this step."""
    return re.sub(r"[^a-z0-9]", "", title.lower().replace(".", "dot"))


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def lightness(hex_colour: str) -> float:
    channels = [int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return (max(channels) + min(channels)) / 2


def service_types() -> list[str]:
    """Every `case` in ServiceType, so a new one cannot ship without an icon decision."""
    source = pathlib.Path("Sources/PortfoxKit/Model/ServiceType.swift").read_text()
    body = source.split("public enum ServiceType", 1)[1].split("public var displayName", 1)[0]
    return re.findall(r"^\s*case (\w+)$", body, re.M)


def write_imageset(service: str, slug: str, svg: str) -> None:
    imageset = DESTINATION / f"service-{service}.imageset"
    imageset.mkdir(exist_ok=True)
    (imageset / f"{slug}.svg").write_text(svg)

    contents = json.loads(json.dumps(CONTENTS))
    contents["images"][0]["filename"] = f"{slug}.svg"
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2))


def main() -> int:
    data = json.loads(fetch(DATA))
    # Slug first, title second. simple-icons carries an explicit `slug` only when
    # it differs from the normalised title, so looking up by title alone breaks
    # every time a project is renamed upstream.
    by_slug = {icon.get("slug") or normalise(icon["title"]): icon["hex"] for icon in data}
    by_title = {icon["title"]: icon["hex"] for icon in data}

    DESTINATION.mkdir(parents=True, exist_ok=True)
    (DESTINATION / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, indent=2)
    )

    # Collected, not raised. Aborting mid-run used to leave the catalogue half
    # updated, and a skipped icon keeps whatever was fetched last time, so one
    # dead slug can never delete a working logo.
    failures: list[tuple[str, str]] = []
    # Several services share one mark: aspNet borrows .NET's and uvicorn used to
    # borrow Gunicorn's. Keyed by slug, so a shared mark is fetched once.
    fetched: dict[str, str] = {}

    for service, (slug, title) in ICONS.items():
        hex_colour = by_slug.get(slug) or by_title.get(title)
        if hex_colour is None:
            failures.append((service, f"no colour for slug {slug!r} or title {title!r}"))
            continue

        if slug not in fetched:
            try:
                fetched[slug] = fetch(RAW.format(slug)).decode()
            except urllib.error.HTTPError as error:
                failures.append((service, f"{slug}.svg: HTTP {error.code}"))
                continue
        svg = fetched[slug]

        fill = "FFFFFF" if lightness(hex_colour) < LIGHTNESS_FLOOR else hex_colour
        write_imageset(service, slug, svg.replace("<path", f'<path fill="#{fill}"', 1))
        print(f"{service:14} {slug:20} #{fill}")

    declared = set(ICONS) | set(NO_BRAND_ICON)
    undeclared = [name for name in service_types() if name not in declared]

    for service, reason in failures:
        print(f"! {service}: {reason}", file=sys.stderr)
    for service in undeclared:
        print(f"! {service}: in neither ICONS nor NO_BRAND_ICON", file=sys.stderr)

    return 1 if failures or undeclared else 0


if __name__ == "__main__":
    sys.exit(main())
