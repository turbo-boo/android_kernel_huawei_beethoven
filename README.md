# android_kernel_huawei_btv

## Runtime accounting and root authorization persistence

The hi3650 defconfig disables `CONFIG_SCHEDSTATS`, but retains
`CONFIG_SCHED_INFO` and task delay accounting. Short Settings scrolling checks
showed no jank before or after this change; they do not establish battery-life
or throughput gains.

KernelSU saves the allowlist to a temporary file, syncs it, atomically renames
it over the committed file, and syncs the parent directory. On legacy ext4 FBE,
the save worker uses a private copy of KernelSU's credentials with init's
session keyring, so encryption-key lookup does not depend on a warm inode
cache. The original credentials, encryption, and SELinux enforcing are retained.

On the d-01J, kernel build #14 successfully persisted grants and revocations
after inode/dentry cache reclamation. An injected temporary-file open failure
preserved the committed file byte-for-byte. A restored Franco Kernel Manager
grant survived two reboots, with actual root child processes observed after
each reboot.

## Zram compression

The hi3650 defconfig enables the zstd crypto compressor used by the device's
zram policy. Compression parameters are selected for `PAGE_SIZE` inputs and
kept fixed per transform so workspace allocation and compression use the
same parameters.

`/sys/module/zstd/parameters/compression_level` defaults to 3 and is clamped
to levels 1 through 22. Set it before creating new zram transforms; each
transform retains the level selected when it was created.