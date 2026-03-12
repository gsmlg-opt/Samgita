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

  scripts.hello.exec = ''
    figlet -w 120 $GREET | lolcat
  '';

  enterShell = ''
    hello
  '';
}
