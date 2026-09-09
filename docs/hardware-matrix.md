# Hardware evidence matrix

This matrix is derived from the supplied runtime, Bluetooth/WLAN, kernel
identity, boot-image, and ramdisk audits. The raw audits were reviewed locally
and are intentionally not stored in this repository. Device identifiers,
serial numbers, account data, PARTUUIDs, and build fingerprints are omitted.

Status vocabulary:

- **Observed on Android**: direct runtime evidence in the supplied audit.
- **Static evidence**: file/config/module metadata only; no runtime proof for a
  custom kernel.
- **Unproven**: requires later device-side acceptance testing.

| Subsystem | Audit evidence | M0/M1 conclusion | Later acceptance gate |
|---|---|---|---|
| Device identity | Model reports Marble on Qualcomm SM7475; compatibles include `qcom,ukee-mtp`, `qcom,ukee`, `qcom,mtp` | Observed on Android; internal platform names may be ukee/cape/anorak rather than `marble` | Preserve DT identity when device integration starts |
| Running kernel | `5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284`; arm64; PREEMPT | ACK 5.10.236 is the version-aligned clean baseline candidate | Boot HyperOS with no regressions at M3 |
| Compiler/security config | Android clang 12.0.5 (`r416183b`); LLD 12.0.5; LTO, Clang CFI, shadow-call-stack enabled | Build with pinned clang-r416183b and keep LTO/CFI/SCS enabled | Compare generated config and runtime behavior |
| GKI/KMI | 356 vendor-ramdisk modules share vermagic `5.10.160-gki-gd28eeb36ae86 SMP preempt mod_unload modversions aarch64`; running kernel is 5.10.236 | Strong static evidence of GKI/KMI plus symbol-versioning dependency; version-string equality is not required | Full symbol CRC check, then load all stock modules without unknown-symbol or CRC errors at M2/M3 |
| Boot image | Android boot header v4; arm64 Image with 4 KiB pages; generic ramdisk LZ4; 4 KiB boot signature | Packaging must preserve v4 semantics; packaging is not part of M1 | Local-only repack and boot test at M3 |
| Vendor boot | Vendor boot header v4; 4 KiB page; LZ4 platform fragment; DTB and 85-byte bootconfig present | Stock vendor_boot remains local and unchanged for baseline | Reuse stock vendor_boot at M3 |
| Bootconfig | `androidboot.hardware=qcom`, `androidboot.memcg=1`, USB controller `a600000.dwc3` | Treat as required packaging inputs | Byte-for-byte semantic verification during local repack |
| Generic ramdisk | `/init` is a KernelSU wrapper; `/init.real` is Android init; `kernelsu.ko` is present | Do not use this wrapper as the dual-boot design | Clean only after source-integrated KernelSU milestone |
| Display | `msm_drm`; `/dev/dri/card0`, `renderD128`; DSI-1 connected/enabled; 1080x2400 at 30/60/90/120 Hz | Observed on Android only | Stable 60 Hz first at M7; higher refresh rates later |
| Touch and keys | Active touch input is `goodix_ts` on event7; power/resin and GPIO keys present; other touch modules are installed but not active | Goodix is source of truth for this panel | Multitouch, coordinates, orientation, libinput at M8 |
| GPU | KGSL `Adreno725v1`; frequencies 220–580 MHz; `msm-adreno-tz`; supplied chroot evidence reports Turnip via Zink | KGSL plus Turnip is a valid phase-1 hypothesis, not an M1 deliverable | Native acceleration at M11 |
| CPU/DVFS | CPU0–3 max 1.8048 GHz; CPU4–6 max 2.496 GHz; CPU7 hardware max 2.9184 GHz; WALT and `qcom-cpufreq-hw` active; CPU7 was capped at 2.2464 GHz in the capture | Do not tune clocks or disable QoS/LMH/thermal policy | Conservative ceiling until native thermal control is proven |
| Thermal | LMH, thermal cooling modules, Xiaomi thermal interface, and userspace QoS writers observed | Safety-critical dependency; Android userspace policy will not exist in native Linux | Sensors, cooling, throttling, and fault behavior before uncapping |
| Battery/charging | `qti_battery_charger`, PMIC GLINK, UCSI GLINK; battery telemetry populated; PD and PD_PPS types advertised | Observed interface availability, not proof of 67 W negotiation | Safe telemetry/charging at M10; negotiated fast charging only at M17 |
| USB-C | `a600000.dwc3`, `dwc3_msm`, UCSI GLINK, Type-C port0; UDC present | Controller path observed; host peripherals were not captured | Mouse, keyboard, storage at M9 |
| Audio | ALSA card `ukee-mtp-snd-card`; LPASS/codec PCM endpoints; AW882xx and WCD937x/WCD938x-related modules; BTFM RX/TX PCM paths | Kernel endpoints exist; safe routing/gain remains unproven | Conservative speaker/mic/USB audio bring-up at M13 |
| Remoteproc/DSP | ADSP, CDSP, MSS, and SLPI all running with named MDT firmware | Firmware availability and sequencing are mandatory | Rootfs firmware staging and remoteproc at M6 |
| Wi-Fi | QCA6490, `qca6490`, `cnss2`, PCI/MHI stack; wlan0 active | Observed on Android; firmware list alone does not identify the minimal native set | Scan, WPA2/WPA3, reconnect at M14 |
| Bluetooth | Qualcomm SoC property `hastings`; `btpower`, `bt_fm_slim`, Slimbus; rfkill entry present but soft-blocked; no `hci` node was captured | Controller transport is not yet proven for native Linux | hci0/rfkill/pair/reconnect/HID/A2DP at M15; HFP mic/SCO at M16 |
| Storage/rootfs | Android `/data` is F2FS with file and metadata encryption tied to Android key handling | `/data/ubuntu` cannot be the initial native rootfs | Initramfs shell, then external USB rootfs; no internal repartitioning |
| AVB/slots | A/B partitions observed; active slot was `_a`; device audit reported unlocked/orange verified-boot state | Informational only; CI must never alter slots or AVB | Any device-side boot action requires a later explicit gate |

## Audit coverage notes

- The boot audit archive contained partition sizes and hashes but no proprietary
  image payloads.
- The ramdisk audit contained the extracted generic/vendor ramdisk, 356 vendor
  modules, module dependency files, fstab, and boot metadata. Only aggregate or
  subsystem-specific facts are retained above.
- Bluetooth audit did not show an HCI device in its capture, so `hci0` is an
  acceptance criterion rather than an established fact.
- Empty sections in an audit are treated as absence of evidence, not evidence
  that the hardware is absent.
