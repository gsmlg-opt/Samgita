# Release scripts

Run from the repository root. These retained helpers do not authorize deployment.
HTTP verification scripts require curl and jq.

- `build-release.sh`: build the two-app release and assets, installing frozen
  JavaScript dependencies from `apps/samgita_web`.
- `docker-build.sh`: build locally; setting a registry also publishes the image
  and requires explicit publishing authorization.
- `health-check.sh [host] [port] [timeout]`: verify HTTP health and database state.
- `smoke-test.sh [base-url] [timeout]`: verify foundation health, info and dashboard.
  This does not prove real Agent WebSocket behavior.
- `deploy.sh`: retained native release upload/start helper.
- `deploy-docker.sh`: retained Compose helper for a prebuilt image.
- `rollback.sh`: restore a release backup; database changes are not rolled back.

Deployment requires separate authorization and later release, fresh-migration,
real Agent WebSocket and health verification. Configure secrets at the destination;
do not upload them with release artifacts. Use a fresh explicitly named database.
Never use legacy release backups as Agent Hub rollback targets.
