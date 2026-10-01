#!/usr/bin/env python3
"""Check the persisted Linux 4.4 manual integration and optional build outputs."""

import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        sys.exit(f"KernelSU Next: {message}")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def check_source():
    entry = git("ls-tree", "HEAD", "KernelSU-Next").split()
    require(len(entry) == 4 and entry[0] == "160000", "missing submodule gitlink")
    require((ROOT / "KernelSU-Next/kernel/Kconfig").is_file(),
            "run git submodule update --init KernelSU-Next first")
    require(git("-C", "KernelSU-Next", "rev-parse", "HEAD") == entry[2],
            "submodule differs from the recorded commit")
    link = ROOT / "drivers/kernelsu"
    require(link.is_symlink() and link.resolve() == ROOT / "KernelSU-Next/kernel",
            "drivers/kernelsu must link to ../KernelSU-Next/kernel")

    hooks = {
        "fs/exec.c": "ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);",
        "fs/open.c": "ksu_handle_faccessat(&dfd, &filename, &mode, NULL);",
        "fs/read_write.c": "ksu_handle_vfs_read(&file, &buf, &count, &pos);",
        "fs/stat.c": "ksu_handle_stat(&dfd, &filename, &flag);",
        "kernel/sys.c": "ksu_handle_setresuid(ruid, euid, suid);",
        "kernel/reboot.c": "ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);",
        "drivers/input/input.c": "ksu_handle_input_handle_event(&type, &code, &value);",
        "security/selinux/hooks.c": "if (is_ksu_transition(old_tsec, new_tsec))",
        "drivers/Makefile": "obj-$(CONFIG_KSU) += kernelsu/",
        "drivers/Kconfig": 'source "drivers/kernelsu/Kconfig"',
    }
    for path, hook in hooks.items():
        require((ROOT / path).read_text().count(hook) == 1,
                f"{path}: missing or duplicate hook: {hook}")
    stat = (ROOT / "fs/stat.c").read_text()
    for name in ("newfstat", "fstat64"):
        require(stat.count(f"if (!error)\n\t\tksu_handle_{name}_ret(&fd, &statbuf);") == 1,
                f"{name} hook must run only after a successful stat copy")

    backports = {
        "include/linux/kernel.h": "#define ALIGN_DOWN(x, a)",
        "include/linux/compiler.h": "#define __nocfi",
        "fs/namespace.c": "int path_umount(struct path *path, int flags)",
        "fs/internal.h": "int path_umount(struct path *path, int flags);",
        "include/linux/seccomp.h": "atomic_t filter_count;",
        "security/selinux/include/objsec.h": "*selinux_cred(const struct cred *cred)",
    }
    for path, marker in backports.items():
        require(marker in (ROOT / path).read_text(), f"{path}: missing {marker}")
    check_config(ROOT / "arch/arm64/configs/hi3650_defconfig")
    print(f"KernelSU Next source verified at {entry[2]}")


def check_config(path):
    lines = path.read_text().splitlines()
    for key in ("KSU", "KSU_MANUAL_HOOK", "SECURITY_SELINUX", "SECCOMP", "KEYS"):
        require(lines.count(f"CONFIG_{key}=y") == 1, f"{path}: CONFIG_{key}=y required")
    # Kconfig omits invisible symbols entirely; both absence and 'not set' are valid.
    for key in ("KSU_KPROBES_HOOK", "KPROBES"):
        require(not any(line.startswith(f"CONFIG_{key}=") for line in lines),
                f"{path}: CONFIG_{key} must be disabled")


def check_build(out):
    check_config(out / ".config")
    for name in ("Image", "Image.gz"):
        path = out / "arch/arm64/boot" / name
        require(path.is_file() and path.stat().st_size > 0, f"missing {path}")
    dtbs = list((out / "arch/arm64/boot/dts/auto-generate").glob("*.dtb"))
    require(dtbs and all(path.stat().st_size > 0 for path in dtbs), "missing hi3650 DTBs")
    symbols = {line.split()[-1] for line in (out / "System.map").read_text().splitlines()}
    for name in ("kernelsu_init", "ksu_handle_execveat", "ksu_handle_vfs_read",
                 "ksu_handle_sys_reboot", "ksu_handle_setresuid",
                 "ksu_handle_input_handle_event", "is_ksu_transition"):
        require(name in symbols, f"KernelSU symbol missing from linked kernel: {name}")
    print(f"KernelSU Next build verified: {out} ({len(dtbs)} DTBs)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="also check a generated .config")
    parser.add_argument("--out", type=Path, help="also check a completed kernel build")
    args = parser.parse_args()
    check_source()
    if args.config:
        check_config(args.config)
    if args.out:
        check_build(args.out)


if __name__ == "__main__":
    main()
