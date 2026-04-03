# Samgita Documentation Index

Welcome to the Samgita documentation. This index provides a structured guide to all documentation by category.

---

## Categories

| Category | Description |
|----------|-------------|
| [Product](#product) | Requirements, vision, and feature specs |
| [Architecture](#architecture) | System design, umbrella structure, integrations |
| [Development](#development) | Setup, conventions, and constitution |
| [API](#api) | REST API reference |
| [Deployment](#deployment) | Production deployment and quickstart guides |
| [CI/CD](#cicd) | Pipeline setup and implementation |

---

## Product

> Requirements and product vision.

- **[prd.md](./prd.md)** — Product Requirements Document (v2): problem, RARV cycle, architecture, agent model, phases, v2 enhancements
- **[design-v2.md](./design-v2.md)** — v2 Design Document: provider evolution, task DAG, plan mode, worker decomposition, inter-agent comms, Synapsis integration
- **[plan.md](./plan.md)** — v2 Implementation Plan: 6-phase roadmap from worker decomposition to Synapsis integration

---

## Architecture

> System design, OTP supervision trees, and integration details.

- **[ARCHITECTURE.md](./architecture/ARCHITECTURE.md)** — Full system architecture: umbrella structure, supervision trees, agent model (RARV), memory system, database schema
- **[DATABASE-ARCHITECTURE.md](./architecture/DATABASE-ARCHITECTURE.md)** — Database design, schema details, pgvector setup, migration strategy
- **[claude-integration.md](./architecture/claude-integration.md)** — Provider abstraction, ClaudeCode CLI integration, configuration, usage patterns

---

## Development

> First-time setup, development conventions, and architectural principles.

- **[GETTING-STARTED.md](./development/GETTING-STARTED.md)** — Installation, first project, dashboard walkthrough, troubleshooting
- **[DEVELOPER-GUIDE.md](./development/DEVELOPER-GUIDE.md)** — Development workflow, code quality tools, testing patterns, database migrations
- **[CONSTITUTION.md](./development/CONSTITUTION.md)** — Core design principles, constraints, and architectural rationale

---

## API

> REST API reference and webhook documentation.

- **[API.md](./api/API.md)** — Complete REST API: endpoints, request/response formats, authentication, rate limiting, webhook payloads, client examples

---

## Deployment

> Production deployment guides.

- **[DEPLOYMENT.md](./deployment/DEPLOYMENT.md)** — Full deployment guide: building releases, environment config, Docker, systemd, Fly.io, security hardening, monitoring
- **[QUICKSTART-DEPLOY.md](./deployment/QUICKSTART-DEPLOY.md)** — Get Samgita running in production in under 5 minutes (Docker, Fly.io, bare metal)

---

## CI/CD

> Continuous integration and deployment pipeline.

- **[CI-CD.md](./ci-cd/CI-CD.md)** — CI/CD overview: GitHub Actions workflows, pipeline structure, environment promotion

---

## Quick Links by Role

### New Users
1. [Getting Started](./development/GETTING-STARTED.md) — setup and first project
2. [README.md](../README.md) — project overview

### Developers
1. [Architecture](./architecture/ARCHITECTURE.md) — system design
2. [Developer Guide](./development/DEVELOPER-GUIDE.md) — workflow and conventions
3. [Claude Integration](./architecture/claude-integration.md) — provider details
4. [CLAUDE.md](../CLAUDE.md) — Claude Code project instructions

### Integrators
1. [API Reference](./api/API.md) — REST endpoints and webhooks

### Operators
1. [Quickstart Deploy](./deployment/QUICKSTART-DEPLOY.md) — fastest path to production
2. [Deployment Guide](./deployment/DEPLOYMENT.md) — full production setup
3. [CI/CD](./ci-cd/CI-CD.md) — pipeline documentation

### Architects
1. [PRD](./prd.md) — product requirements (v2)
2. [Design v2](./design-v2.md) — v2 design document
3. [Architecture](./architecture/ARCHITECTURE.md) — system design
4. [Database Architecture](./architecture/DATABASE-ARCHITECTURE.md) — data model
5. [Constitution](./development/CONSTITUTION.md) — design principles

---

## Glossary

| Term | Definition |
|------|-----------|
| **RARV Cycle** | Reason → Act → Reflect → Verify — atomic unit of agent work |
| **PRD** | Product Requirements Document |
| **Agent** | Specialized AI worker (one of 37 types across 7 swarms) |
| **Orchestrator** | `gen_statem` managing project lifecycle phases |
| **Provider** | LLM integration abstraction (ClaudeCode, Codex) |
| **Horde** | Distributed process registry and supervisor |
| **Oban** | Background job queue and scheduler |
| **pgvector** | PostgreSQL extension for vector similarity search |
| **LiveView** | Phoenix real-time UI framework |
| **Umbrella** | Elixir multi-app project structure |
| **DAG** | Directed Acyclic Graph — task dependency graph within each phase |
| **Wave** | Set of tasks with no unresolved dependencies, dispatched together |
| **Session** | Long-lived provider connection maintaining conversation state across RARV cycles |
| **MessageRouter** | Per-project GenServer routing inter-agent messages |
| **Plan Mode** | Optional phase converting an idea into a structured PRD |

---

**Last Updated:** 2026-04-03
