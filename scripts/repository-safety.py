#!/usr/bin/env python3
"""Read-only, redacted publication gate. Never stages, commits, pushes or deletes."""
import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "Google API key": rb"\bAIza[A-Za-z0-9_-]{30,}",
    "Discord webhook": rb"https://(?:discord(?:app)?\.com)/api/webhooks/\d+/[A-Za-z0-9_-]+",
    "bearer credential": rb"(?i)bearer\s+[A-Za-z0-9_.~-]{16,}",
    "credential assignment": rb'''(?im)\b(?:password|passwd|api[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|signing[_-]?password)\s*[:=]\s*["'][^"'\r\n]{8,}["']''',
    "credential URL": rb"https?://[^\s/:]+:[^\s/@]+@",
    "machine-specific path": rb"/Users" + rb"/[^/\s<>]+/",
}
EXTENSIONS = {".p12", ".pfx", ".cer", ".crt", ".key", ".pem", ".mobileprovision",
              ".zip", ".tar", ".gz", ".tgz", ".7z", ".dmg", ".pkg", ".log",
              ".tmp", ".temp", ".keychain", ".keychain-db"}
DIRS = {"build", "dist", ".build", ".swiftpm", ".module-cache", ".swiftpm-cache",
        ".cache", "__pycache__", "DerivedData", "xcuserdata", "diagnostics", "logs", "tmp", "work"}

def git(*args, check=True):
    return subprocess.run(["git", "-C", str(ROOT), *args], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check).stdout

def report(path, line, kind):
    # Only metadata, never the matching value or source line.
    print(f"BLOCK: {path}:{line}: {kind}")

def forbidden(path):
    p = pathlib.PurePosixPath(path)
    name = p.name.lower()
    return (any(x in DIRS or x.endswith((".app", ".dSYM")) for x in p.parts)
            or p.suffix.lower() in EXTENSIONS
            or (name != ".env.example" and (name == ".env" or name.startswith(".env.") or name.endswith(".env")))
            or name in {".ds_store", ".netrc", ".npmrc", ".pypirc", "credentials.json"}
            or path == "Support/DevelopmentSigning.conf")

def scan(path, data, check_path=True):
    failures = 0
    if check_path and forbidden(path):
        report(path, 0, "excluded sensitive/local/archive path")
        failures += 1
    for kind, pattern in PATTERNS.items():
        for match in re.finditer(pattern, data):
            report(path, data[:match.start()].count(b"\n") + 1, kind)
            failures += 1
    if pathlib.PurePosixPath(path).name == ".env.example":
        for i, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not re.fullmatch(r"[A-Z][A-Z0-9_]*=(?:|YOUR_[A-Z0-9_]+|your_[a-z0-9_]+_here|<[^<>]+>)", line):
                report(path, i, "example value not an approved placeholder")
                failures += 1
    return failures

def audit_local():
    failures = 0
    for p in ROOT.rglob("*"):
        relative = p.relative_to(ROOT).as_posix()
        if any(part in DIRS or part == ".git" or part.endswith(".app") for part in p.relative_to(ROOT).parts):
            continue
        if p.is_symlink():
            report(relative, 0, "symlink requires review")
            failures += 1
        elif p.is_file():
            # Binary reference images are reviewed separately; never dump pixels/metadata.
            if p.suffix.lower() in {".png", ".icns"}:
                continue
            failures += scan(relative, p.read_bytes())
    return failures

def entries(tree=None):
    if tree:
        raw = git("ls-tree", "-r", "-z", tree)
        for entry in raw.split(b"\0"):
            if entry:
                meta, path = entry.split(b"\t", 1)
                mode, kind, oid = meta.split()
                yield mode, oid, path.decode("utf-8", "surrogateescape"), kind
    else:
        for entry in git("ls-files", "--stage", "-z").split(b"\0"):
            if entry:
                meta, path = entry.split(b"\t", 1)
                mode, oid, stage = meta.split()
                if stage != b"0":
                    raise RuntimeError("Unmerged index; publication blocked")
                yield mode, oid, path.decode("utf-8", "surrogateescape"), b"blob"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["local", "staged", "history"])
    mode = parser.parse_args().mode
    if mode == "local":
        count = audit_local()
    else:
        top = pathlib.Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve()
        if top != ROOT:
            print("BLOCK: Git root is not the NoMenu project. Ancestor repository left untouched.")
            return 2
        print("Staged paths:")
        for p in git("diff", "--cached", "--name-only", "-z").split(b"\0"):
            if p:
                print(repr(p.decode("utf-8", "surrogateescape")))
        groups = [entries()]
        if mode == "history":
            groups += [entries(commit) for commit in git("rev-list", "--all").decode().splitlines()]
        count, seen = 0, set()
        for group in groups:
            for filemode, oid, path, kind in group:
                identity = (filemode, oid, path)
                if identity in seen:
                    continue
                seen.add(identity)
                ignored = subprocess.run(
                    ["git", "-C", str(ROOT), "check-ignore", "--no-index", "-q", "--", path],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE
                ).returncode
                if ignored not in (0, 1):
                    raise RuntimeError("Cannot verify ignore policy")
                if ignored == 0 and not forbidden(path):
                    report(path, 0, "tracked/history file excluded by current ignore policy")
                    count += 1
                if filemode in {b"120000", b"160000"} or kind != b"blob":
                    report(path, 0, "symlink/submodule requires independent audit")
                    count += 1
                    continue
                count += scan(path, git("cat-file", "blob", oid.decode()))
    print(f"Heuristic findings: {count}. Manual/binary review and maintained secret scan remain required.")
    return 1 if count else 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        print("BLOCK: audit could not complete; no publication allowed.")
        sys.exit(2)
