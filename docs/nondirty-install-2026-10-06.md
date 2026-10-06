# Nondirty Full LTO kernel installation, 2026-10-06

The operator requested installing the corrected kernel, removing the `-dirty`
release suffix, updating this project's report, and then resuming work in the
separate native Linux repository. This request authorized replacement of the
current slot's `boot_a` with the exact locally staged candidate below.

## Build and local identity

- Source commit: `54aeb9d60c70a53f1e6b55f79ecb700d45445914`.
- [Canonical GitHub-hosted Full LTO run 37167145926](https://github.com/binxgtl/marble-kernelsu-susfs/actions/runs/37167145926): `static-and-regression` PASS, `build-full-lto` PASS, overall PASS.
- Downloaded artifact: `susfs-nomount-full-lto-54aeb9d60c70a53f1e6b55f79ecb700d45445914-37167145926`.
- Kernel release: `5.10.236-gb97c62c4e7d1`. The downloaded Image contains this release and no occurrence of that release with `-dirty` appended.
- Image SHA256: `9c59d76b6ea867f6c3b2b67b9f490045c0f03bf6c3d46f190f5401829c149f86`; size 48,199,156 bytes.
- Config SHA256: `9a29112c3128cb90ea52a682393fbf51721f2aa22e6f71e8b5d5cb903c550707`.
- Feature lock SHA256: `f4be8f5ed8f2b21cb470b073e43b4bff8ed034243cfd5b0e0b2096cc9d1fb52b`.
- Full LTO, CFI, shadow call stack, MODVERSIONS, KernelSU Next, SUSFS and NoMount remain configured. Linked built-in metadata contains the exact NoMount v20 records.
- Independent local KMI rerun: 14,614 exports with canonical digest `72c9fb8e915500074f0b5382371441c14c9054852cf79d808f365723d9d57295`; all 18,368 stock-provider requirements matched, with zero missing, CRC mismatches, ambiguous or invalid resolutions.

Two independent local repacks against canonical stock boot produced byte-identical
images and the same ramdisk SHA256
`9cce5e72d95d18a7947697b41b34cee1bde57dd93a22152e70146126f2053ac6`.
The staged boot image is 49,586,176 bytes, SHA256
`17ded6d89e641725791a1ac237b8aa18f9bf518e26105890f0d94bef71cd39c2`.
The staging script's generic unsigned-image warning was resolved by the
temporary boot test below before the persistent installation.

## Device sequence

Read-only preflight found serial `136a0bb6`, Android boot complete, `marble`,
slot `_a`, green verified boot, the previously installed
`5.10.236-gb97c62c4e7d1-dirty` kernel, 418 loaded modules, all four expected
remoteprocs running with their expected firmware, and 93% battery.

Fastboot confirmed product `marble`, current slot `a`, unlocked `yes`, and
`boot_a` size `0xC000000`. At `2026-10-06T11:58:06.8814573Z`, one temporary
`fastboot boot` of the exact candidate returned rc=0 at
`11:58:08.5845304Z`. Its output reported sending and booting OKAY. Android was
boot complete by `11:58:33.6450001Z`; read-only checks found the nondirty
release, slot `_a`, green verified boot, 418 modules and ADSP/CDSP/MSS/SLPI
running with the expected firmware.

After that test, fastboot again confirmed the same device, slot, unlocked state
and partition size. The locally retained previous installed image, SHA256
`9d8ca0df6a00c09f34d93f93bf76ad5c85b8ec3713dfae88b0a8dc344051f5ba`,
and full 192 MiB recovery backup, SHA256
`7c121279cd1dfaaf1cab74ac64720c6962d4553646f0e44ec0c3f882d243e923`,
were rehashed before writing.

Exactly one `fastboot flash boot_a` of the tested candidate started at
`2026-10-06T11:59:32.3114072Z` and returned rc=0 at `11:59:33.8114754Z`:

```text
Sending 'boot_a' (48424 KB)                        OKAY [  1.343s]
Writing 'boot_a'                                   OKAY [  0.039s]
Finished. Total time: 1.435s
```

The following ordinary `fastboot reboot` returned rc=0. Android was boot
complete by `12:00:09.9470165Z`. The final read-only audit at
`12:00:43.2731025Z` confirmed `marble`, slot `_a`, green verified boot,
`5.10.236-gb97c62c4e7d1`, 418 modules and all four expected remoteprocs
running. `/proc/config.gz` exposed Full LTO, CFI, shadow call stack,
MODVERSIONS, KSU, SUSFS and NoMount enabled.

The earlier installed kernel remains recoverable from the retained local image;
the full recovery backup remains separate. The bootloader cannot fetch the
partition, so the written partition was not independently hashed after flash.
The verified Android release and normal boot are evidence that the intended
replacement ran. No other partition, AVB, slot or bootloader state was changed
by the recorded fastboot commands. This installation authorization is consumed.

This is a **temporary and persistent Android boot PASS** for the nondirty build.
It does not establish root shell through ADB, NoMount redirection, SUSFS hiding
rules, long-term stability, or the cause of the 418-versus-stock-419 module
count. Local detailed evidence remains ignored under
`artifacts/boot-test-37167145926/` and
`artifacts/persistent-install-37167145926/`.
