# android_kernel_huawei_btv

## Zram compression

The hi3650 defconfig enables the zstd crypto compressor used by the device's
zram policy. Compression parameters are selected for `PAGE_SIZE` inputs and
kept fixed per transform so workspace allocation and compression use the
same parameters.

`/sys/module/zstd/parameters/compression_level` defaults to 3 and is clamped
to levels 1 through 22. Set it before creating new zram transforms; each
transform retains the level selected when it was created.
