#!/usr/bin/env python3
"""Regression checks for pinned integration, padding port and source isolation."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("features", ROOT / "scripts/integrate-features.py")
FEATURES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FEATURES)
META_SPEC = importlib.util.spec_from_file_location("metadata", ROOT / "scripts/verify-builtin-metadata.py")
METADATA = importlib.util.module_from_spec(META_SPEC)
META_SPEC.loader.exec_module(METADATA)


class IntegrationTest(unittest.TestCase):
    def test_linked_builtin_metadata_rejects_wrong_or_missing_nomount(self):
        valid = b"other.version=20\0nomount.version=20\0nomount.file=fs/nomount/nomount\0"
        builtin = "kernel/fs/nomount/nomount.ko\n"
        METADATA.verify(valid, builtin)
        for invalid in (b"", valid[:-1], valid.replace(b"nomount.version=20", b"nomount.version=19"),
                        valid.replace(b"nomount.version=20", b"other.version=20"),
                        valid.replace(b"nomount.file=fs/nomount/nomount", b"nomount.file=elsewhere")):
            with self.subTest(metadata=invalid), self.assertRaises(ValueError):
                METADATA.verify(invalid, builtin)
        with self.assertRaises(ValueError):
            METADATA.verify(valid, "kernel/fs/other/nomount.ko\n")

    def test_exact_source_pins_and_full_lto(self):
        lock = FEATURES.load_lock(ROOT / "manifests/features.lock.json")
        expected = {
            "ack": "b97c62c4e7d1e80fb6a2cb0cb381f03bbcd26a4e",
            "clang": "54220fd601050b350b2af7adc913089ebf0e7aed",
            "kernelsu": "4c5853188012f63a1a1fedd4a57fda6375fecb38",
            "susfs": "9892175b4acec7ee844e113b8d02c0f4d12cdfac",
            "nomount": "5a610db7649a59eb3e3d710653618d594941f8da",
        }
        self.assertEqual({k: v["commit"] for k, v in lock["inputs"].items()}, expected)
        ksu = lock["inputs"]["kernelsu"]
        self.assertEqual(30000 + ksu["commit_count"], ksu["in_tree_version"])
        self.assertEqual(lock["lto"], "full")
        for name in ("ack-common", "clang-r416183b"):
            lines = (ROOT / "manifests/sources.lock").read_text().splitlines()
            entry = next(line.split("|") for line in lines if line.startswith(name + "|"))
            item = lock["inputs"]["ack" if name == "ack-common" else "clang"]
            self.assertEqual(entry[2], item["url"])
            self.assertEqual(entry[4], item["commit"])

    def test_nonimmutable_pin_is_rejected(self):
        lock = json.loads((ROOT / "manifests/features.lock.json").read_text())
        lock["inputs"]["susfs"]["commit"] = "gki-android12-5.10"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "lock.json"
            path.write_text(json.dumps(lock))
            with self.assertRaisesRegex(ValueError, "non-immutable"):
                FEATURES.load_lock(path)

    def test_padding_hunk_is_explicit_and_no_features_are_removed(self):
        hunk = ("@@ -906,6 +944,13 @@ static int show_smap(struct seq_file *m, void *v)\n"
                " \tstruct vm_area_struct *vma = v;\n"
                " \tstruct mem_size_stats mss;\n"
                "+#ifdef CONFIG_KSU_SUSFS_SUS_MAP\n"
                "+\tif (vma->vm_file)\n"
                "+\t\treturn 0;\n"
                " \tmemset(&mss, 0, sizeof(mss));\n")
        result = FEATURES.port_patch(hunk.encode()).decode()
        self.assertIn("@@ -906,7 +944,14 @@", result)
        self.assertIn("pad_vma = get_pad_vma(v)", result)
        self.assertIn("vma = get_data_vma(v)", result)
        self.assertIn("CONFIG_KSU_SUSFS_SUS_MAP", result)
        self.assertIn("memset(&mss, 0, sizeof(mss))", result)
        for invalid in (hunk.replace("vma = v", "vma = changed"), hunk + hunk):
            with self.assertRaisesRegex(ValueError, "manual review"):
                FEATURES.port_patch(invalid.encode())

    def test_ksu_version_does_not_depend_on_remote_branch(self):
        item = FEATURES.load_lock(ROOT / "manifests/features.lock.json")["inputs"]["kernelsu"]
        text = ("objects unchanged\n# Check if this is a git repository\n"
                "KSU_GIT_VERSION := $(shell git merge-base HEAD origin/main)\n"
                "KSU_NEW_DCACHE_FLUSH := unchanged\n")
        result = FEATURES.pinned_kbuild(text, item)
        self.assertNotIn("merge-base", result)
        self.assertNotIn("$(shell git", result)
        self.assertIn("KSU_VERSION := 33321", result)
        self.assertIn("KSU_VERSION_TAG := v3.4.0", result)
        self.assertTrue(result.startswith("objects unchanged\n"))
        self.assertTrue(result.endswith("KSU_NEW_DCACHE_FLUSH := unchanged\n"))
        with self.assertRaises(ValueError):
            FEATURES.pinned_kbuild("unknown Kbuild", item)

    def test_add_line_preserves_nested_kconfig(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "Kconfig"
            path.write_text('menu "outer"\nmenu "inner"\nendmenu\nendmenu\n')
            FEATURES.add_line(path, 'source "fs/nomount/Kconfig"', True)
            self.assertEqual(path.read_text(), 'menu "outer"\nmenu "inner"\nendmenu\nsource "fs/nomount/Kconfig"\nendmenu\n')
            with self.assertRaises(ValueError):
                FEATURES.add_line(path, 'source "fs/nomount/Kconfig"', True)

    def test_full_lto_keeps_cfi_scs_and_kmi_checks(self):
        fragment = (ROOT / "configs/features.fragment").read_text()
        for setting in ("CONFIG_LTO_CLANG_FULL=y", "CONFIG_CFI_CLANG=y",
                        "CONFIG_SHADOW_CALL_STACK=y", "CONFIG_MODVERSIONS=y",
                        "CONFIG_KEYS=y", "CONFIG_NOMOUNT=y", "CONFIG_KSU_SUSFS=y"):
            self.assertIn(setting, fragment.splitlines())
        self.assertIn("# CONFIG_LTO_CLANG_THIN is not set", fragment.splitlines())
        builder = (ROOT / "scripts/build-kernel.sh").read_text()
        self.assertIn('scripts/verify-features-config.sh "$out_dir/.config"', builder)
        self.assertIn("lto_mode=full", builder)
        workflow = (ROOT / ".github/workflows/susfs-nomount.yml").read_text()
        self.assertNotIn("self-hosted", workflow)
        self.assertNotIn("marble-builder", workflow)
        self.assertIn("ubuntu-24.04", workflow)
        self.assertIn("m4-kmi-digest.py", workflow)
        self.assertIn("--expect-manifest manifests/kmi-baseline.txt", workflow)
        self.assertIn("m2-verify-kmi.py", workflow)
        self.assertNotIn("continue-on-error: true", workflow)

    def test_original_config_requirements_are_preserved_except_lto_choice(self):
        original = (ROOT / "scripts/verify-config.sh").read_text()
        current = (ROOT / "scripts/verify-features-config.sh").read_text()
        pattern = r"^\s+(CONFIG_[A-Z0-9_]+=\w+)\s*$"
        old_requirements = set(re.findall(pattern, original, re.M))
        new_requirements = set(re.findall(pattern, current, re.M))
        self.assertEqual(old_requirements - new_requirements, {"CONFIG_LTO_CLANG_THIN=y"})

    def test_actual_config_verifier_accepts_full_and_rejects_weakened_configs(self):
        bash = "C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else shutil.which("bash")
        self.assertTrue(bash and Path(bash).exists(), "native Bash required, never WSL")
        verifier = ROOT / "scripts/verify-features-config.sh"
        required = re.findall(r"^\s+(CONFIG_[A-Z0-9_]+=\w+)\s*$", verifier.read_text(), re.M)
        valid = "\n".join(required + ["# CONFIG_LTO_CLANG_THIN is not set"]) + "\n"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config"
            def check(text):
                path.write_text(text, encoding="utf-8", newline="\n")
                return subprocess.run([bash, verifier.as_posix(), path.as_posix()], capture_output=True).returncode
            self.assertEqual(check(valid), 0)
            for removed in ("CONFIG_LTO_CLANG_FULL=y", "CONFIG_CFI_CLANG=y",
                            "CONFIG_SHADOW_CALL_STACK=y", "CONFIG_MODVERSIONS=y",
                            "CONFIG_KEYS=y", "CONFIG_KSU_SUSFS=y", "CONFIG_NOMOUNT=y"):
                with self.subTest(removed=removed):
                    self.assertNotEqual(check(valid.replace(removed + "\n", "")), 0)
            self.assertNotEqual(check(valid.replace("# CONFIG_LTO_CLANG_THIN is not set", "CONFIG_LTO_CLANG_THIN=y")), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
