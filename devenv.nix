{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  pkgs-stable = import inputs.nixpkgs-stable {system = pkgs.stdenv.system;};
in {
  env.GREET = "Samgita";
  env.NODE_PATH = "${toString ./.}/deps";
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
  languages.elixir.package = pkgs-stable.beam28Packages.elixir;

  services.postgres = {
    enable = true;
    package = pkgs-stable.postgresql_16;
    listen_addresses = "";
    initialDatabases = [
      {name = "samgita_hub_dev";}
      {name = "samgita_hub_test";}
    ];
    settings = {
      port = lib.mkForce 5433;
      unix_socket_directories = "${config.env.DEVENV_STATE}/postgres";
    };
  };

  processes.samgita = {
    exec = "mix samgita.run";
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
    echo "  mix samgita.run — start Phoenix server (port 3110)"
    echo "  setup       — first-time DB setup (mix ecto.setup)"
    echo "  mix test    — run tests"
  '';
}
