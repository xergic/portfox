#!/usr/bin/env python3
"""Fetch framework logos from simple-icons into the app asset catalogue.

Icon paths are CC0. The trademarks remain the property of their owners, and are
used here only to identify the software each service is running.

Run from the repository root:  python3 Tools/fetch-icons.py
"""
import json
import pathlib
import sys
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


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def lightness(hex_colour: str) -> float:
    channels = [int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return (max(channels) + min(channels)) / 2


def main() -> int:
    colours = {icon["title"]: icon["hex"] for icon in json.loads(fetch(DATA))}
    DESTINATION.mkdir(parents=True, exist_ok=True)
    (DESTINATION / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, indent=2)
    )

    for service, (slug, title) in ICONS.items():
        if title not in colours:
            print(f"! no colour for {title}", file=sys.stderr)
            return 1

        hex_colour = colours[title]
        fill = "FFFFFF" if lightness(hex_colour) < LIGHTNESS_FLOOR else hex_colour
        svg = fetch(RAW.format(slug)).decode()
        svg = svg.replace("<path", f'<path fill="#{fill}"', 1)

        imageset = DESTINATION / f"service-{service}.imageset"
        imageset.mkdir(exist_ok=True)
        (imageset / f"{slug}.svg").write_text(svg)

        contents = json.loads(json.dumps(CONTENTS))
        contents["images"][0]["filename"] = f"{slug}.svg"
        (imageset / "Contents.json").write_text(json.dumps(contents, indent=2))
        print(f"{service:14} {slug:20} #{fill}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
