.DEFAULT_GOAL := help
SCHEME := Portfox
PROJECT := Portfox.xcodeproj
CONFIG := Debug
DERIVED := build

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

gen: ## Regenerate the Xcode project from project.yml
	xcodegen generate --quiet

build: ## Build the SwiftPM core
	swift build

test: ## Run the core test suite
	swift test

scan: ## Resolve services on this machine
	@swift build 2>/dev/null && ./.build/debug/portfox-scan $(ARGS)

raw: ## Print every listener with process metadata
	@swift build 2>/dev/null && ./.build/debug/portfox-scan --raw

app: gen ## Build the menu bar app
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build | tail -5

run: app ## Build and launch the menu bar app
	@pkill -x Portfox || true
	@open $(DERIVED)/Build/Products/$(CONFIG)/Portfox.app

snapshot: app ## Render popover, dashboard, preferences, ignored and about snapshots to snapshots/
	@mkdir -p snapshots
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot snapshots/popover.png
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-dashboard snapshots/dashboard.png
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-prefs snapshots/preferences.png
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-ignored snapshots/ignored.png
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-about snapshots/about.png
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot snapshots/arrived.png --arrived
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot snapshots/popover-light.png --light
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-dashboard snapshots/dashboard-light.png --light
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-prefs snapshots/preferences-light.png --light
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-ignored snapshots/ignored-light.png --light
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot-about snapshots/about-light.png --light
	@$(DERIVED)/Build/Products/$(CONFIG)/Portfox.app/Contents/MacOS/Portfox --snapshot snapshots/arrived-light.png --arrived --light

archive: ## Build a universal ad hoc signed Release app and DMG into dist/
	@Tools/archive.sh $(VERSION)

lint: ## Run SwiftLint
	swiftlint lint --quiet

clean: ## Remove build artefacts
	rm -rf .build $(DERIVED) $(PROJECT) snapshots dist

.PHONY: help gen build test scan raw app run snapshot archive lint clean
