# Independent marble KernelSU Next / SUSFS / NoMount project

Speak Vietnamese to the operator; write source and documentation in English.
This repository is independent of `D:\idk.omg\marble-native-linux`. Do not edit
that repository, its branches, manifests, historical binaries or milestones.

The operator explicitly requested on 2026-10-04:
- Start from the completed M4 project commit
  `d9d2c1e03ee81fa61feb79138c402fb8cc04bc00`.
- Pin SUSFS to `9892175b4acec7ee844e113b8d02c0f4d12cdfac`.
- Prioritize SUSFS and NoMount; retain KernelSU Next as the only root engine.
- Use GitHub-hosted Actions workers and **Full LTO** for this project.

Those instructions override the original project's self-hosted/ThinLTO policy
only here. Do not install local compiler toolchains or use WSL/SSH builds.
Preserve the ACK and clang pins, CFI, shadow call stack and MODVERSIONS.
Require the frozen exported-symbol digest and the provider-aware stock-module
gate; never remove version/CRC checks to make modules load.

Public source-only CI: never upload stock boot images, ROM payloads, DTBs or
proprietary vendor modules. Stage Android boot images locally only after every
build/KMI gate passes. Stop before hardware and report the exact candidate.
No flash, partition writes, AVB changes, slot changes or bootloader changes.
The preceding emergency boot_a restore was a separate, completed authorization.

Pin every fetched component to an immutable commit. Do not execute floating
upstream setup scripts. Record modifications, input hashes, generated config,
compiler identity and logs. Do not claim build, root, SUSFS or NoMount runtime
success without actual evidence.
