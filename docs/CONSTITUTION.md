# Samgita Constitution

## Core Architectural Principles

This document outlines the fundamental design decisions and principles that govern the Samgita project.

---

## No Authentication or Account System

**Decision:** Samgita does not implement user authentication, account management, or access control systems.

**Rationale:**

1. **Deployment Model**: Samgita is designed to be deployed as a local or private development tool, not a multi-tenant SaaS application.

2. **Access Model**: Anyone who can access the Samgita instance is inherently trusted and has full administrative privileges. Access control is enforced at the infrastructure/network level (firewall, VPN, localhost binding), not at the application level.

3. **Simplicity**: Removing authentication complexity allows the system to focus on its core mission: orchestrating AI agent swarms for software development.

4. **Zero Configuration**: No user registration, password management, session handling, or permission systems to configure or maintain.

5. **Self-Hosted Philosophy**: Samgita follows the self-hosted/personal tool philosophy where the deployment owner controls physical access to the system.

**Implications:**

- No login/logout flows
- No user profiles or preferences stored in database
- No role-based access control (RBAC)
- No API keys or authentication tokens for web interface
- All actions in audit logs are attributed to "system" or identified by session/IP

**Security Model:**

Security is provided through:
- **Network isolation**: Run on localhost or behind VPN/firewall
- **Infrastructure access control**: SSH keys, server access permissions
- **Physical security**: Control of the machine running Samgita
- **API rate limiting**: Prevent abuse from rogue scripts/bots
- **Audit logging**: Track all actions for accountability

**When This Decision Should Be Revisited:**

This decision should be reconsidered if:
- Samgita becomes a hosted service offering
- Multiple organizations need to share a single deployment
- Compliance requirements mandate user-level access tracking
- Community requests strongly favor multi-user support

Until then, **anyone who can access Samgita is an admin**.

---

## Additional Principles

### 1. Git as Source of Truth

Projects are identified by their `git_url`, not by internal database IDs. This allows projects to be portable across deployments and machines.

### 2. Postgres Over Mnesia

All persistent state lives in PostgreSQL, not in-memory or distributed Erlang databases. This eliminates split-brain scenarios and simplifies backup/recovery.

### 3. Distributed by Design

Samgita uses Horde for process distribution and Oban for job distribution, allowing horizontal scaling without code changes.

### 4. RARV Cycle is Sacred

The Reason-Act-Reflect-Verify cycle is the fundamental workflow pattern for all agents. This structure cannot be bypassed or short-circuited.

### 5. Claude CLI Over Direct API

Samgita uses the Claude CLI tool (via ClaudeAgentSDK) instead of direct API calls. This reuses host authentication and simplifies deployment.

---

## Enforcement

These principles are enforced through:
- Code review and pull request guidelines
- Architectural Decision Records (ADRs) for major changes
- This constitution document as the authoritative reference

Any changes to these core principles require explicit discussion and documentation updates.

---

**Last Updated:** 2026-02-04
**Status:** Active
