# Changelog

All notable changes to TripSplit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project foundation:
  - Flutter application scaffold (Material 3) with minimal runnable shell.
  - Feature-first Clean Architecture layout under `lib/features`.
  - Offline-first local SQLite database via Drift (schema, DAOs, migration strategy).
  - Riverpod dependency injection foundation and GoRouter navigation graph.
  - Material 3 theme foundation (colors, typography, spacing, component themes).
  - Application error hierarchy (`AppException`, `DatabaseException`, `ValidationException`, `RepositoryException`).
  - Domain entities and repository interfaces for trips, members, contributions, expenses, and settlements.
  - Unit/widget tests and integration test scaffolding.
- Development infrastructure:
  - Docker development environment (`Dockerfile`, `docker-compose.yml`, `.dockerignore`).
  - `Makefile` with reproducible containerized commands.
  - GitHub Actions CI workflow (format, analyze, test, APK build).
  - Project documentation, `CHANGELOG.md`, and `.env.example`.