# Samgita Agent Guidance

Read [AGENTS.md](AGENTS.md) for repository instructions.

Samgita is undergoing the approved clean-start Agent Hub rebuild. The target is two applications, `samgita` and `samgita_web`, with all execution performed by external Agents. The old provider/memory applications, local workers, PRD orchestrator, and their associated product surfaces are being removed.

Authoritative documents:

- [Product requirements](docs/prd.md)
- [Architecture and protocol contracts](docs/architecture.md)
- [Implementation plan](docs/plan.md)
- [Approved design](docs/agent-hub-rebuild-design.md)
- [Removal inventory](docs/agent-hub-removal-inventory.md)

The source tree still contains legacy code until implementation stages remove it. Do not infer a compatibility requirement from that code or resurrect instructions from the former product.

Use only the active stage's scope and tests. Preserve unrelated changes, place worktrees under `.trees/`, and follow the upstream dependency issue-routing rules in AGENTS.md.
