# Rootfs build script for lenovo y700 gen 2

<p align="center">English | <a href="/README.th.md">ภาษาไทย</a> </p>

---

## Descriptions
Scripts and device support for running **Arch Linux ARM** on the
**Lenovo Legion Y700 (2023)** — model `TB320FC`, codename `asphalt`.

## Disclaimer
- This project is based on [torvalds/linux](https://github.com/torvalds/linux). Stability is questionable and depends on how heavy the merge commit is.
- I take **zero** responsibility if something goes wrong, or if you get fired because Slack video calls break, or Microsoft Teams stops working after a kernel update. If you point at me for that, I’ll laugh at you.
- This is **not** a complete, plug-and-play rootfs. You must build the dependencies yourself.
- i'm not gonna submit this to LKML, dealing with android giving me enough headache, i didn't want an extras

## Resources

- [What’s working](#whats-working)
- [Building (kernel + packaging)](scripts/kernel/README.md)
- [Relock bootloader](#relock-bootloader)

## What’s working

| Component | Notes |
| --- | --- |
| **Audio** | Cirrus Logic CS35L45, available upstream |
| **Wi-Fi / Bluetooth** | WCN6855, upstream code |
| **CPU** | Octa-core (1×3.19 GHz Cortex-X2 + 3×2.75 GHz Cortex-A710 + 4×1.80 GHz Cortex-A510) |
| **GPU** | Adreno 730 as Freedreno 725 (`0x07030002`). [Reference](https://raw.githubusercontent.com/termux/termux-packages/f8013fe24f/packages/mesa/0016-unofficial_support_adreno_710_720_722.patch) |
| **Display** | 30/60/120/144 Hz reported correctly. VRR from ~48 Hz up to 144 Hz. 30 Hz is supported in hardware, but Lenovo never set `mdss-dsi-qsync-min-refresh-rate` to 30, so the default floor is currently 48 Hz. [Reference](https://github.com/lolipuru/kernel_lenovo_sm8475-devicetrees/blob/lineage-24.0/qcom/display/display/cape-sde-display-common.dtsi) |
| **microSD** | Tested with SanDisk Ultra (A1) |
| **Touch** | Novatek NT36523n — upstream + device-specific changes |
| **Fuel gauge** | Basic battery report + charging via upstream code |
| **Camera** | ROW and PRC ship different modules. This tree targets the ROW set (`ov13b10`, `s5k4h7`, `sc202cs`) |
| **USB** | Working, including DP-alt, DP-alt audio, and dual-port arbitration (same behaviour as stock ZUI) |
| **UFS** | Working. Limited to HS-GEAR4 (Rate A) because of the UFS hardware itself |
| **Iris (VPU)** | Hardware accelerated on V4L2. VA-API needs [qcom-va-driver](https://github.com/radxa-pkg/qcom-va-driver) |
| **Haptics** | AW86927 — upstream + small dual-haptics changes. Currently 7 SRAM firmwares loaded; plan to push all 138 RTP effects later |
| **Sensors** | Auto-brightness, lid-cover suspend, gyroscope. CDSP / SDSP / ADSP working |
| **Suspend** | Works via normal sleep + power button. s2idle / deep, both are now working |
| **Charging** | Bypass charging works (`pmic-glink` ported from SM8550, Lenovo supply props from NEC kernel source) |
| **Thermal** | Working. Power profiles included |

## What doesn’t work / TO-DO

| Component | Notes |
| --- | --- |
| **HDR** | External monitor (DHI-PM19-S201S) doesn’t support HDR. Internal panel HDR is on the TO-DO list |
| **AV1** | Software only. Qualcomm only started hardware AV1 on SM8550 and later — middle finger from qcom |
| **Stylus** | AP500U / AP501U and Precision Pen 2. which i don’t have |

## Technical notes
| Component | Notes |
| --- | --- |
| **WIFI** | ath11k have D3cold failure which is unique to lenovo (lmao), so 2s firmware reload after suspend is normal, WoW policy won't works there [Reference](https://lore-kernel.gnuweeb.org/ath11k/0fbb0b6e-c849-4e26-9c46-2ac4986f6b52@hauke-m.de/t/) |

## Relock bootloader

Are you fucking serious?

It’s doable — this tablet uses AVBv2 with avb-custom-keys support — but I can’t stop you.

**Requirements**

- Brain, and ability to read and think carefully
- Actual knowledge of AOSP build systems
- Understand how AVBv2 works
- Know How to sign images with your own private key

TO-DO, i didn't want some users report with bricked tablet

## Dual booting

doable, if you aren't stupid, it's possible by using slots B as

- ZUI* only take slots A, you can repartition userdata and use boot, dtbo and vendor_boot into slot b
- if you want to dual boot with other OS like lineage, Crdroid or whatever you want, must be installed with fastboot packages
- if you want triple booting (eg: with unixnu or mu-silicium), you must use another method or find way to boot over sdcard

* if you're using zui as main OSes, be careful as some firmware, booting to B guarantee to get you into brazil (EDL)

## Issues report and AI policy

- i **don't** give a fuck on AI involved as this start as personal project.
- however, any report that use LLM assisted must be test and validated from user first, and must be able to answer my question if i doubt on the methods, any issue or PR with LLM assisted straight from ass without test and validated from user **will be closed immediately** 