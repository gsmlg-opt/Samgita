{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  pkgs-stable = import inputs.nixpkgs-stable {system = pkgs.stdenv.system;};
  # Touched by `samgita-watch` after a debounced change; `samgita` restarts on it.
  restartStamp = "${config.env.DEVENV_STATE}/samgita.restart";
in {
  env.GREET = "Samgita";
  # Disable the Erlang break menu so Ctrl+C (and devenv's SIGTERM on restart)
  # stops `mix samgita.run` instead of leaving the BEAM at a BREAK prompt.
  env.ELIXIR_ERL_OPTIONS = "+B";
  env.NODE_PATH = "${toString ./.}/deps";

  packages = with pkgs-stable;
    [
      git
      figlet
      lolcat
      watchman
    ]
    ++ lib.optionals stdenv.isLinux [
      inotify-tools
    ];

  languages.elixir.enable = true;
  languages.elixir.package = pkgs-stable.beam28Packages.elixir;

  # Unix socket only (no TCP listener, so no port conflicts with other
  # projects). The module puts the socket in this project's runtime directory
  # and exports PGHOST; config/dev.exs and config/test.exs connect through it.
  services.postgres = {
    enable = true;
    package = pkgs-stable.postgresql_16;
    listen_addresses = "";
    initialDatabases = [
      {name = "samgita_hub_dev";}
      {name = "samgita_hub_test";}
    ];
  };

  processes.samgita = {
    after = ["devenv:processes:postgres"];
    exec = ''
      set -e
      mix deps.get
      mix ecto.create --quiet
      mix ecto.migrate
      exec mix samgita.run
    '';

    # Restarted (debounced) by `samgita-watch`; see below.
    watch.paths = [restartStamp];

    ready = {
      http.get = {
        host = "127.0.0.1";
        port = 4870;
        path = "/";
      };
      period = 1;
      probe_timeout = 5;
      # A first boot compiles every dependency.
      timeout = 600;
    };
  };

  # Phoenix reloads application code in place, but configuration, Mix project
  # files and dependencies are only read at boot. A burst of changes (a git
  # pull, `mix deps.get`/`deps.update`) restarts the server once, after 15s
  # without further changes. devenv's own `watch` has no debounce. Linux only
  # (inotify-tools).
  processes.samgita-watch = lib.mkIf pkgs.stdenv.isLinux {
    exec = ''
      set -eu
      mkdir -p deps
      inotifywait -m -r -q -e close_write,create,delete,move --format '%w%f' \
        config mix.exs mix.lock apps/samgita/mix.exs apps/samgita_web/mix.exs deps |
        grep --line-buffered -E '(\.exs|\.lock|/\.hex|hex_metadata\.config)$' |
        while read -r changed; do
          echo "changed: $changed (restarting samgita after 15s without changes)"
          while read -r -t 15 changed; do :; done
          echo "restarting samgita"
          # A content write: devenv's watcher ignores metadata-only `touch`.
          date +%s%N > ${lib.escapeShellArg restartStamp}
        done
    '';
  };

  # The watched stamp must exist before `samgita` starts watching it.
  tasks."samgita:restart-stamp" = {
    exec = "[ -e ${lib.escapeShellArg restartStamp} ] || : > ${lib.escapeShellArg restartStamp}";
    before = ["devenv:processes:samgita"];
  };

  scripts.hello.exec = ''
    figlet -w 120 $GREET | lolcat
  '';

  # Remove all Mix build output and fetched dependencies (the umbrella plus the
  # standalone protocol/driver projects and their examples), then fetch the
  # locked deps again. Never touches mix.lock, the database or node_modules.
  # A running `devenv up` restarts and recompiles once the fetch settles.
  scripts.clean.exec = ''
    set -eu
    cd "$DEVENV_ROOT"
    echo "==> Removing Mix build output and dependencies..."
    rm -rf _build deps apps/*/_build apps/*/deps apps/*/examples/*/_build apps/*/examples/*/deps
    echo "==> Fetching locked dependencies..."
    mix deps.get
    echo "==> Done. The next compile rebuilds everything."
  '';

  scripts.setup.exec = ''
    echo "==> Setting up databases..."
    mix ecto.setup
    echo "==> Done! Run 'devenv up' to start all services."
  '';

  enterShell = ''
    hello
    echo ""
    echo "Commands:"
    echo "  devenv up   — start PostgreSQL + Phoenix server (restarts on config/mix changes)"
    echo "  mix samgita.run — start Phoenix server (port 4870)"
    echo "  setup       — first-time DB setup (mix ecto.setup)"
    echo "  clean       — remove all _build/deps output and refetch locked deps"
    echo "  mix test    — run tests"
  '';
}
