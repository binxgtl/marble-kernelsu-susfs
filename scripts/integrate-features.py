#!/usr/bin/env python3
"""Pinned source integration; no upstream setup scripts or KMI bypasses."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
PATCH = "kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def load_lock(path: Path) -> dict:
    lock = json.loads(path.read_text(encoding="utf-8"))
    if lock.get("schema") != 1 or lock.get("lto") != "full":
        raise ValueError("unexpected lock schema or LTO")
    for name in ("ack", "clang", "kernelsu", "susfs", "nomount"):
        item = lock["inputs"][name]
        if not re.fullmatch(r"[0-9a-f]{40}", item["commit"]):
            raise ValueError(f"{name}: non-immutable pin")
        if not item["url"].startswith("https://"):
            raise ValueError(f"{name}: invalid source URL")
        if Path(item["directory"]).name != item["directory"]:
            raise ValueError(f"{name}: invalid directory")
    return lock


def fetch(root: Path, item: dict, full: bool = False) -> None:
    repo = root / item["directory"]
    if not (repo / ".git").exists():
        if full:
            subprocess.run(["git", "-c", "core.autocrlf=false", "clone",
                            item["url"], str(repo)], check=True)
        else:
            subprocess.run(["git", "init", str(repo)], check=True)
            git(repo, "config", "core.autocrlf", "false")
            git(repo, "remote", "add", "origin", item["url"])
    if git(repo, "status", "--porcelain"):
        raise ValueError(f"refusing to overwrite modified source: {repo}")
    if git(repo, "remote", "get-url", "origin").removesuffix(".git") != item["url"].removesuffix(".git"):
        raise ValueError(f"wrong source remote: {repo}")
    git(repo, "config", "core.autocrlf", "false")
    args = ["fetch", "--no-tags"]
    if not full:
        args.append("--depth=1")
    git(repo, *args, "origin", item["commit"])
    if full:
        git(repo, "fetch", "--tags", "origin")
        if (repo / ".git/shallow").exists():
            git(repo, "fetch", "--unshallow", "origin")
    git(repo, "checkout", "--detach", item["commit"])


def port_patch(data: bytes) -> bytes:
    # The upstream patch expects vma=v. This exact ACK has VMA padding helpers.
    # Preserve both ACK declarations and its existing memset/show_pad flow.
    text = data.decode("utf-8")
    old = ("@@ -906,6 +944,13 @@ static int show_smap(struct seq_file *m, void *v)\n"
           " \tstruct vm_area_struct *vma = v;\n"
           " \tstruct mem_size_stats mss;\n")
    new = ("@@ -906,7 +944,14 @@ static int show_smap(struct seq_file *m, void *v)\n"
           " \tstruct vm_area_struct *pad_vma = get_pad_vma(v);\n"
           " \tstruct vm_area_struct *vma = get_data_vma(v);\n"
           " \tstruct mem_size_stats mss;\n")
    if text.count(old) != 1:
        raise ValueError("SUSFS show_smap hunk changed; manual review required")
    return text.replace(old, new, 1).encode("utf-8")


def pinned_kbuild(text: str, item: dict) -> str:
    # Upstream computes a merge-base with a remote branch at build time.
    # Freeze the count/tag from this exact full-depth commit instead.
    start = "# Check if this is a git repository\n"
    end = "KSU_NEW_DCACHE_FLUSH :="
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError("unrecognized KSU Kbuild version block")
    before, rest = text.split(start, 1)
    _version, after = rest.split(end, 1)
    version = item["in_tree_version"]
    tag = item["version"]
    block = ("# Version frozen from the verified full-depth source pin.\n"
             f"KSU_VERSION := {version}\n"
             f"KSU_VERSION_TAG := {tag}\n"
             "$(info -- KernelSU-Next version: $(KSU_VERSION))\n"
             "$(info -- KernelSU-Next tag: $(KSU_VERSION_TAG))\n"
             "ccflags-y += -DKSU_VERSION=$(KSU_VERSION)\n"
             'ccflags-y += -DKSU_VERSION_TAG=\\"$(KSU_VERSION_TAG)\\"\n\n')
    return before + block + end + after


def add_line(path: Path, line: str, before_last_endmenu: bool = False) -> None:
    text = path.read_text(encoding="utf-8")
    if line in text:
        raise ValueError(f"integration already present: {path}")
    if before_last_endmenu:
        offset = text.rfind("\nendmenu")
        if offset < 0:
            raise ValueError(f"missing endmenu: {path}")
        text = text[:offset] + "\n" + line + text[offset:]
    else:
        text = text.rstrip() + "\n\n" + line + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def integrate(root: Path, lock: dict, check_only: bool) -> dict:
    inputs = lock["inputs"]
    repos = {name: root / item["directory"] for name, item in inputs.items()}
    for name in ("ack", "kernelsu", "susfs", "nomount"):
        repo = repos[name]
        if git(repo, "rev-parse", "HEAD") != inputs[name]["commit"]:
            raise ValueError(f"{name}: wrong source revision")
        if git(repo, "status", "--porcelain"):
            raise ValueError(f"{name}: source is modified; use a fresh build tree")
    ksu = repos["kernelsu"]
    if (ksu / ".git/shallow").exists():
        raise ValueError("KSU history must be full depth")
    if int(git(ksu, "rev-list", "--count", "HEAD")) != inputs["kernelsu"]["commit_count"]:
        raise ValueError("KSU commit count mismatch")
    if git(ksu, "describe", "--tags", "--abbrev=0") != inputs["kernelsu"]["version"]:
        raise ValueError("KSU tag mismatch")
    for filename, expected in inputs["susfs"]["files"].items():
        if sha((repos["susfs"] / filename).read_bytes()) != expected:
            raise ValueError(f"SUSFS file identity mismatch: {filename}")
    for repo, subtree in ((ksu, "kernel"), (repos["nomount"], "kernel/src")):
        for source in (repo / subtree).rglob("*"):
            if source.suffix in (".c", ".h") and re.search(
                r"^\s*EXPORT_SYMBOL(?:_GPL)?\s*\(", source.read_text(), re.M
            ):
                raise ValueError(f"unexpected new kernel exports: {source}")
    header = (repos["susfs"] / "kernel_patches/include/linux/susfs.h").read_text()
    if f'#define SUSFS_VERSION "{inputs["susfs"]["version"]}"' not in header:
        raise ValueError("SUSFS version mismatch")
    kbuild = pinned_kbuild((ksu / "kernel/Kbuild").read_text(), inputs["kernelsu"])
    original_patch = (repos["susfs"] / PATCH).read_bytes()
    ported = port_patch(original_patch)
    ack = repos["ack"]
    # Check every hunk before modifying the tree. No fuzz, rejects or ignores.
    with tempfile.TemporaryDirectory(prefix="susfs-port-") as temporary:
        patch = Path(temporary) / "susfs.patch"
        patch.write_bytes(ported)
        git(ack, "apply", "--check", str(patch))
        if not check_only:
            git(ack, "apply", str(patch))
    if not check_only:
        for filename in ("fs/susfs.c", "include/linux/susfs.h", "include/linux/susfs_def.h"):
            shutil.copyfile(repos["susfs"] / "kernel_patches" / filename, ack / filename)
        (ksu / "kernel/Kbuild").write_text(kbuild, encoding="utf-8", newline="\n")
        for destination, source in ((ack / "drivers/kernelsu", ksu / "kernel"),
                                    (ack / "fs/nomount", repos["nomount"] / "kernel/src")):
            if destination.exists() or destination.is_symlink():
                raise ValueError(f"refusing to replace integration path: {destination}")
            destination.symlink_to(os.path.relpath(source, destination.parent), target_is_directory=True)
        add_line(ack / "drivers/Makefile", "obj-$(CONFIG_KSU) += kernelsu/")
        add_line(ack / "drivers/Kconfig", 'source "drivers/kernelsu/Kconfig"', True)
        add_line(ack / "fs/Makefile", "obj-$(CONFIG_NOMOUNT) += nomount/")
        add_line(ack / "fs/Kconfig", 'source "fs/nomount/Kconfig"', True)
    return {"status": "PATCH_CHECK_PASS" if check_only else "INTEGRATED_NOT_BUILT",
            "pins": {name: item["commit"] for name, item in inputs.items()},
            "upstream_patch_sha256": sha(original_patch),
            "ported_patch_sha256": sha(ported), "pinned_kbuild_sha256": sha(kbuild.encode()),
            "port": "show_smap context only; retain get_pad_vma/get_data_vma and memset",
            "lto": "full", "hardware": "NOT TESTED"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("work"))
    parser.add_argument("--lock", type=Path, default=PROJECT / "manifests/features.lock.json")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--report", type=Path, default=Path("artifacts/integration-report.json"))
    args = parser.parse_args()
    lock = load_lock(args.lock)
    root = args.root.resolve()
    if args.fetch:
        root.mkdir(parents=True, exist_ok=True)
        for name in ("kernelsu", "susfs", "nomount"):
            fetch(root, lock["inputs"][name], full=name == "kernelsu")
    report = integrate(root, lock, args.check_only)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
