#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# KernelSU Next legacy HEAD checked on 2026-08-26.
# Pin the source so CI and local builds do not silently change behavior.
KSU_REF="${KSU_REF:-a54e4fa46c6cc25bcaa055cf14d790194beffed8}"
KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/legacy/kernel/setup.sh"

if [[ ! -f KernelSU-Next/kernel/Kconfig ]]; then
    echo "[+] Fetching KernelSU Next legacy at ${KSU_REF}"
    curl -fLSs "$SETUP_URL" | bash -s "$KSU_REF"
else
    current_ref="$(git -C KernelSU-Next rev-parse HEAD)"
    if [[ "$current_ref" != "$KSU_REF" ]]; then
        echo "[+] Updating KernelSU Next ${current_ref} -> ${KSU_REF}"
        git -C KernelSU-Next fetch origin "$KSU_REF"
        git -C KernelSU-Next checkout --detach "$KSU_REF"
    fi
fi

# Keep the KernelSU source as a pinned submodule instead of vendoring it.
if [[ ! -f .gitmodules ]]; then
    cat > .gitmodules <<EOF
[submodule "KernelSU-Next"]
	path = KernelSU-Next
	url = ${KSU_REPO}
EOF
elif ! grep -Fq 'path = KernelSU-Next' .gitmodules; then
    cat >> .gitmodules <<EOF

[submodule "KernelSU-Next"]
	path = KernelSU-Next
	url = ${KSU_REPO}
EOF
fi

# setup.sh normally creates these. Re-assert them for subsequent submodule checkouts.
ln -sfn ../KernelSU-Next/kernel drivers/kernelsu
if ! grep -Fq 'obj-$(CONFIG_KSU) += kernelsu/' drivers/Makefile; then
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
fi
if ! grep -Fq 'source "drivers/kernelsu/Kconfig"' drivers/Kconfig; then
    sed -i '/^endmenu$/i\source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi

cat > include/linux/kernelsu.h <<'EOF'
#ifndef _LINUX_KERNELSU_H
#define _LINUX_KERNELSU_H

#include <linux/fs.h>
#include <linux/types.h>
#include <linux/uidgid.h>

struct filename;
struct stat;
struct stat64;

#ifdef CONFIG_KSU
int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
                        void *argv, void *envp, int *flags);
int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
                        int *mode, int *flags);
int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,
                        size_t *count_ptr, loff_t **pos);
void ksu_handle_newfstat_ret(unsigned int *fd,
                             struct stat __user **statbuf);
void ksu_handle_fstat64_ret(unsigned long *fd,
                            struct stat64 __user **statbuf);
int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);
int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,
                          void __user **arg);
int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code,
                                  int *value);
#else
static inline int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
                                      void *argv, void *envp, int *flags)
{
    return 0;
}
static inline int ksu_handle_faccessat(int *dfd,
                                       const char __user **filename_user,
                                       int *mode, int *flags)
{
    return 0;
}
static inline int ksu_handle_stat(int *dfd,
                                  const char __user **filename_user,
                                  int *flags)
{
    return 0;
}
static inline int ksu_handle_vfs_read(struct file **file_ptr,
                                      char __user **buf_ptr,
                                      size_t *count_ptr, loff_t **pos)
{
    return 0;
}
static inline void ksu_handle_newfstat_ret(unsigned int *fd,
                                           struct stat __user **statbuf)
{
}
static inline void ksu_handle_fstat64_ret(unsigned long *fd,
                                          struct stat64 __user **statbuf)
{
}
static inline int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)
{
    return 0;
}
static inline int ksu_handle_sys_reboot(int magic1, int magic2,
                                        unsigned int cmd, void __user **arg)
{
    return 0;
}
static inline int ksu_handle_input_handle_event(unsigned int *type,
                                                unsigned int *code,
                                                int *value)
{
    return 0;
}
#endif

#endif /* _LINUX_KERNELSU_H */
EOF

python3 <<'PY'
from pathlib import Path


def read(path):
    return Path(path).read_text()


def write(path, data):
    Path(path).write_text(data)


def ensure_include(path, anchor):
    s = read(path)
    include = '#include <linux/kernelsu.h>\n'
    if include in s:
        return
    if anchor not in s:
        raise SystemExit(f'include anchor not found in {path}: {anchor!r}')
    write(path, s.replace(anchor, anchor + include, 1))


def insert_after(path, scope, anchor, addition, marker):
    s = read(path)
    if marker in s:
        return
    scope_pos = s.find(scope)
    if scope_pos < 0:
        raise SystemExit(f'scope not found in {path}: {scope!r}')
    anchor_pos = s.find(anchor, scope_pos)
    if anchor_pos < 0:
        raise SystemExit(f'anchor not found in {path}: {anchor!r}')
    anchor_pos += len(anchor)
    s = s[:anchor_pos] + addition + s[anchor_pos:]
    write(path, s)


# Common declarations and manual hooks for Linux 4.4.
ensure_include('fs/exec.c', '#include <linux/syscalls.h>\n')
insert_after(
    'fs/exec.c',
    'static int do_execveat_common(',
    '\tif (IS_ERR(filename))\n\t\treturn PTR_ERR(filename);\n',
    '\n\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n',
    'ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);',
)

ensure_include('fs/open.c', '#include <linux/syscalls.h>\n')
insert_after(
    'fs/open.c',
    'SYSCALL_DEFINE3(faccessat,',
    '\tunsigned int lookup_flags = LOOKUP_FOLLOW;\n',
    '\n\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n',
    'ksu_handle_faccessat(&dfd, &filename, &mode, NULL);',
)

ensure_include('fs/read_write.c', '#include <linux/syscalls.h>\n')
insert_after(
    'fs/read_write.c',
    'ssize_t vfs_read(',
    '\tssize_t ret;\n',
    '\n\tksu_handle_vfs_read(&file, &buf, &count, &pos);\n',
    'ksu_handle_vfs_read(&file, &buf, &count, &pos);',
)

ensure_include('fs/stat.c', '#include <linux/syscalls.h>\n')
insert_after(
    'fs/stat.c',
    'int vfs_fstatat(',
    '\tunsigned int lookup_flags = 0;\n',
    '\n\tksu_handle_stat(&dfd, &filename, &flag);\n',
    'ksu_handle_stat(&dfd, &filename, &flag);',
)
insert_after(
    'fs/stat.c',
    'SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)',
    '\tif (!error)\n\t\terror = cp_new_stat(&stat, statbuf);\n',
    '\n\tksu_handle_newfstat_ret(&fd, &statbuf);\n',
    'ksu_handle_newfstat_ret(&fd, &statbuf);',
)
insert_after(
    'fs/stat.c',
    'SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)',
    '\tif (!error)\n\t\terror = cp_new_stat64(&stat, statbuf);\n',
    '\n\tksu_handle_fstat64_ret(&fd, &statbuf);\n',
    'ksu_handle_fstat64_ret(&fd, &statbuf);',
)

ensure_include('kernel/reboot.c', '#include <linux/syscalls.h>\n')
insert_after(
    'kernel/reboot.c',
    'SYSCALL_DEFINE4(reboot,',
    '\tint ret = 0;\n',
    '\n\tret = ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n\tif (ret)\n\t\treturn ret;\n',
    'ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);',
)

ensure_include('kernel/sys.c', '#include <linux/syscalls.h>\n')
insert_after(
    'kernel/sys.c',
    'SYSCALL_DEFINE3(setresuid,',
    '\tkuid_t kruid, keuid, ksuid;\n',
    '\n\tksu_handle_setresuid(ruid, euid, suid);\n',
    'ksu_handle_setresuid(ruid, euid, suid);',
)

# Manual safe-mode hook. Keep this outside input core's spinlock.
ensure_include('drivers/input/input.c', '#include <linux/rcupdate.h>\n')
insert_after(
    'drivers/input/input.c',
    'void input_event(struct input_dev *dev,',
    '\tunsigned long flags;\n',
    '\n\tksu_handle_input_handle_event(&type, &code, &value);\n',
    'ksu_handle_input_handle_event(&type, &code, &value);',
)

# Linux <= 4.19 needs to allow init -> KernelSU SELinux transition under NNP/nosuid.
selinux_path = 'security/selinux/hooks.c'
s = read(selinux_path)
extern_marker = 'extern bool is_ksu_transition('
if extern_marker not in s:
    anchor = '/* binprm security operations */\n'
    addition = (
        '\n#ifdef CONFIG_KSU\n'
        'extern bool is_ksu_transition(const struct task_security_struct *old_tsec,\n'
        '\t\t\t      const struct task_security_struct *new_tsec);\n'
        '#endif\n'
    )
    if anchor not in s:
        raise SystemExit('SELinux binprm anchor not found')
    s = s.replace(anchor, anchor + addition, 1)

transition_marker = 'if (is_ksu_transition(old_tsec, new_tsec))'
if transition_marker not in s:
    scope = 'static int check_nnp_nosuid('
    scope_pos = s.find(scope)
    if scope_pos < 0:
        raise SystemExit('SELinux check_nnp_nosuid not found')
    anchor = '\tif (new_tsec->sid == old_tsec->sid)\n\t\treturn 0; /* No change in credentials */\n'
    anchor_pos = s.find(anchor, scope_pos)
    if anchor_pos < 0:
        raise SystemExit('SELinux transition anchor not found')
    anchor_pos += len(anchor)
    addition = (
        '\n#ifdef CONFIG_KSU\n'
        '\tif (is_ksu_transition(old_tsec, new_tsec))\n'
        '\t\treturn 0;\n'
        '#endif\n'
    )
    s = s[:anchor_pos] + addition + s[anchor_pos:]
write(selinux_path, s)

# Force the correct hook mode for this kernel: KPROBES is disabled in hi3650_defconfig.
config_path = Path('arch/arm64/configs/hi3650_defconfig')
lines = config_path.read_text().splitlines()
keys = ('KSU', 'KSU_MANUAL_HOOK', 'KSU_KPROBES_HOOK')
filtered = []
for line in lines:
    if any(line.startswith(f'CONFIG_{k}=') or line == f'# CONFIG_{k} is not set' for k in keys):
        continue
    filtered.append(line)
filtered += [
    '',
    '# KernelSU Next',
    'CONFIG_KSU=y',
    'CONFIG_KSU_MANUAL_HOOK=y',
    '# CONFIG_KSU_KPROBES_HOOK is not set',
]
config_path.write_text('\n'.join(filtered) + '\n')
PY

echo "[+] KernelSU Next ${KSU_REF} integrated with Linux 4.4 manual hooks"
