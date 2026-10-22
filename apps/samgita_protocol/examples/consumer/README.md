# Standalone consumer

This is a separate Mix project with only a relative path dependency on `samgita_protocol`. Copy the protocol directory anywhere and this example still builds. It does not load the repository's umbrella, configuration, database, Phoenix endpoint, or optional adapters.

From this directory, using Elixir 1.18+:

```sh
mix deps.get
mix test
mix run -e 'IO.inspect(StandaloneConsumer.run())'
```

The host implements only `project_events.v1`. It receives an event twice with different delivery attempts, retains one original event, records an explicit decision and queries status. Its state is in memory: receipt means `received`, and decision recording returns `management_acceptance: not_requested`. No reasoning loop, task transition, implicit approval, durable inbox, or listener is involved. A real host must persist its inbox and command receipts and enforce authentication/authorization at its own boundary.

The test also checks that no platform applications or new socket/port handles start. For a real `/app-server` fake Agent and bidirectional client example, see [the optional WebSocket package](../../../samgita_protocol_websocket/README.md).
