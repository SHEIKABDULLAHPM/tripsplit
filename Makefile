# TripSplit development commands.
#
# All commands run inside the `trip_split_dev` Docker service, making the
# development environment reproducible across machines. Raw Flutter/Dart
# variants are provided as `*-local` targets for machines with a local SDK.

DC      ?= docker compose
SERVICE ?= trip_split_dev
RUN     := $(DC) run --rm --no-deps $(SERVICE)

.PHONY: help
help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

## -- Docker lifecycle ---------------------------------------------------------

.PHONY: docker-build
docker-build: ## Build the development image
	$(DC) build $(SERVICE)

.PHONY: docker-pull
docker-pull: ## Pull the base Flutter image
	$(DC) pull $(SERVICE)

.PHONY: up
up: ## Start the development container as a daemon
	$(DC) up -d $(SERVICE)

.PHONY: down
down: ## Stop and remove the development container
	$(DC) down

.PHONY: volume-clean
volume-clean: ## Remove dependency cache volumes (forces full re-download)
	$(DC) down -v

## -- Flutter / Dart commands ---------------------------------------------------

.PHONY: setup
setup: docker-build pub-get generate ## Initialize the development environment

.PHONY: doctor
doctor: ## Run Flutter/environment diagnostics
	$(RUN) bash docker/scripts/doctor.sh

.PHONY: get
get: ## flutter pub get
	$(RUN) flutter pub get

.PHONY: generate
generate: ## Run build_runner code generation
	$(RUN) dart run build_runner build

.PHONY: analyze
analyze: ## Static analysis
	$(RUN) flutter analyze

.PHONY: format
format: ## Format all Dart sources
	$(RUN) dart format .

.PHONY: format-check
format-check: ## Verify formatting without modifying files
	$(RUN) dart format --output=none --set-exit-if-changed .

.PHONY: test
test: ## Run unit/widget tests
	$(RUN) flutter test

.PHONY: build
build: ## Build the release APK
	$(RUN) flutter build apk --release

.PHONY: build-debug
build-debug: ## Build the debug APK
	$(RUN) flutter build apk --debug

.PHONY: clean
clean: ## flutter clean
	$(RUN) flutter clean

.PHONY: shell
shell: ## Open a shell inside the development container
	$(DC) run --rm --no-deps --entrypoint bash $(SERVICE)

## -- Local SDK variants (no Docker required) -----------------------------------

.PHONY: get-local
get-local: ## flutter pub get (local SDK)
	flutter pub get

.PHONY: generate-local
generate-local: ## build_runner code generation (local SDK)
	dart run build_runner build

.PHONY: analyze-local
analyze-local: ## Static analysis (local SDK)
	flutter analyze

.PHONY: format-local
format-local: ## Format all Dart sources (local SDK)
	dart format .

.PHONY: test-local
test-local: ## Run unit/widget tests (local SDK)
	flutter test

.PHONY: build-local
build-local: ## Build the release APK (local SDK)
	flutter build apk --release