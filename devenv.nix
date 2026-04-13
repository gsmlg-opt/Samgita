{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  pkgs-stable = import inputs.nixpkgs-stable {system = pkgs.stdenv.system;};
  pkgs-unstable = import inputs.nixpkgs-unstable {system = pkgs.stdenv.system;};
in {
  env.GREET = "Samgita";
  env.MIX_BUN_PATH = lib.getExe pkgs-stable.bun;
  env.MIX_TAILWIND_PATH = lib.getExe pkgs-stable.tailwindcss_4;
  env.PGHOST = "${config.env.DEVENV_STATE}/postgres";
  env.POSTGRES_PORT = "5433";

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
  languages.elixir.package = pkgs-stable.beam27Packages.elixir;

  languages.javascript.enable = true;
  languages.javascript.pnpm.enable = true;
  languages.javascript.bun.enable = true;
  languages.javascript.bun.package = pkgs-stable.bun;

  services.postgres = {
    enable = true;
    package = pkgs-stable.postgresql_16;
    extensions = ext: [ext.pgvector];
    listen_addresses = "";
    initialDatabases = [
      {name = "samgita_dev";}
      {name = "samgita_test";}
    ];
    settings.unix_socket_directories = "${config.env.DEVENV_STATE}/postgres";
  };

  processes.samgita = {
    exec = "mix phx.server";
    process-compose = {
      depends_on.postgres.condition = "process_healthy";
    };
  };

  scripts.hello.exec = ''
    figlet -w 120 $GREET | lolcat
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
    echo "  devenv up   — start PostgreSQL + Phoenix server"
    echo "  setup       — first-time DB setup (mix ecto.setup)"
    echo "  mix test    — run tests"
  '';
}
