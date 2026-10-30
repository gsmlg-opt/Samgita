#!/usr/bin/env python3
"""Compile extracted Hex archives in an outside consumer without starting any application."""

import argparse
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

from release import PACKAGES, version_parts


def verify(directory, version):
    version_parts(version)
    with tempfile.TemporaryDirectory(prefix="samgita-hex-consumer-") as temporary:
        root = Path(temporary)
        for name in PACKAGES:
            archive = directory / name / f"{name}-{version}.tar"
            with tarfile.open(archive) as package:
                contents = package.extractfile("contents.tar.gz").read()
            with tarfile.open(fileobj=io.BytesIO(contents), mode="r:gz") as sources:
                sources.extractall(root / "packages" / name, filter="data")
        consumer = root / "consumer"
        consumer.mkdir()
        dependencies = ",\n".join(
            f'        {{:{name}, path: "../packages/{name}", override: true}}' for name in PACKAGES
        )
        (consumer / "mix.exs").write_text(
            "defmodule ReleaseConsumer.MixProject do\n"
            "  use Mix.Project\n"
            "  def project do\n"
            "    [app: :release_consumer, version: \"0.0.0\", elixir: \"~> 1.18\", deps: [\n"
            + dependencies + "\n    ]]\n  end\nend\n"
        )
        environment = {
            **os.environ,
            "MIX_ENV": "prod",
            "MIX_BUILD_PATH": str(consumer / "_build"),
            "MIX_DEPS_PATH": str(consumer / "deps"),
        }
        for arguments in (("deps.get",), ("compile", "--warnings-as-errors")):
            subprocess.run(["mix", *arguments], cwd=consumer, env=environment,
                           check=True, timeout=360)
        checks = "\n".join(
            f'true = Application.load(:{name}) in [:ok, {{:error, {{:already_loaded, :{name}}}}}]\n'
            f'true = to_string(Application.spec(:{name}, :vsn)) == "{version}"'
            for name in PACKAGES
        )
        checks += '\nfalse = Code.ensure_loaded?(Samgita.Repo)\nfalse = Code.ensure_loaded?(Phoenix)\n'
        subprocess.run(["mix", "run", "--no-start", "--no-compile", "-e", checks],
                       cwd=consumer, env=environment, check=True, timeout=60)
        print(f"Outside consumer compiled all {len(PACKAGES)} extracted packages at {version}; no application started.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    verify(args.directory.resolve(), args.version)


if __name__ == "__main__":
    main()
