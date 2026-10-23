#!/usr/bin/env python3
"""Prime the documented Rustler cache for the Linux GNU conformance job.

GitHub release redirects exceed retained httpc's 10 KiB header limit. Download
the unchanged MDEx artifact with HTTPS, verifying the locked package's checksum;
RustlerPrecompiled independently checks that checksum again before extraction.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
MAX_BYTES = 16 * 1024 * 1024


def artifact(root):
    lock = (root / "mix.lock").read_text()
    version = re.search(r'^\s*"mdex_native": \{:hex, :mdex_native, "(\d+\.\d+\.\d+)"',
                        lock, re.MULTILINE)
    if not version:
        raise ValueError("a locked mdex_native release is required")
    version = version[1]
    name = f"libmdex_native_nif-v{version}-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz"
    checksums = root / "deps/mdex_native/checksum-Elixir.MDExNative.Native.exs"
    matches = re.findall(r'"' + re.escape(name) + r'"\s*=>\s*"sha256:([0-9a-f]{64})"',
                         checksums.read_text())
    if len(matches) != 1:
        raise ValueError("exactly one locked package checksum is required")
    url = f"https://github.com/leandrocp/mdex_native/releases/download/v{version}/{name}"
    return name, matches[0], url


class ReleaseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        destination = urllib.parse.urlsplit(newurl)
        if (destination.scheme != "https" or destination.username or destination.password
                or destination.hostname not in {"github.com", "release-assets.githubusercontent.com"}):
            raise ValueError("unexpected release redirect destination")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def prime(root, cache, opener=None):
    name, checksum, url = artifact(root)
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / name
    if destination.exists():
        if hashlib.sha256(destination.read_bytes()).hexdigest() != checksum:
            raise ValueError("existing cached artifact checksum mismatch")
        return destination

    opener = opener or urllib.request.build_opener(ReleaseRedirect())
    request = urllib.request.Request(url, headers={"User-Agent": "Samgita-Conformance-NIF/1"})
    # Public HTTPS only; never send account credentials or log signed redirect URLs.
    with opener.open(request, timeout=30) as response:
        if response.status != 200:
            raise ValueError("release download did not return HTTP 200")
        body = response.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise ValueError("release artifact exceeds the bounded download size")
    if hashlib.sha256(body).hexdigest() != checksum:
        raise ValueError("downloaded artifact checksum mismatch")

    with tempfile.NamedTemporaryFile(dir=cache, prefix=".samgita-nif-", delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path,
                        default=os.environ.get("RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH"))
    args = parser.parse_args()
    if args.cache_dir is None:
        parser.error("explicit cache directory or RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH required")
    destination = prime(ROOT, args.cache_dir)
    print(f"Verified locked MDEx native artifact: {destination.name}")


if __name__ == "__main__":
    main()
