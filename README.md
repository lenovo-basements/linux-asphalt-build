# Rootfs build script for lenovo y700 gen 2

<p align="center">
  <img width="1051" height="657" alt="image" src="https://github.com/user-attachments/assets/6bbcf9a0-ddd8-4c07-b14d-f9828ae97f9e" />
  <img width="1051" height="657" alt="image" src="https://github.com/user-attachments/assets/d335d65b-66d6-4138-8bd4-7c8437d3622a" />
</p>

<p align="center"> <a href="https://www.pixiv.net/en/artworks/151930453">wallpaper</a></p>

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

- [Kernel source](https://github.com/lenovo-basements/lenovo-sm8475-mainline)
- [Firmware repo](https://github.com/lenovo-basements/asphalt-firmware)
- [What’s working](#whats-working)
- [Build instructions](scripts/README.md)
- [Relock bootloader](#relock-bootloader)
- <a href="/docs/camera.md">the rant: camera</a>

## What’s working

| Component | Notes |
| --- | --- |
| **Audio** | Cirrus Logic CS35L45, using available upstream, the rest are standard `ALSA` and `UCM` via `pipewire` (`EasyEffects` is recommend, the initial audio is bad, even on AOSP) |
| **Wi-Fi / Bluetooth** | WCN6855, using upstream code (WCN6855 firmware is from `liquin` (Xiaomi Pad 6 Pro), `OS3.0.7.0.VMYCNXM` due to stock lenovo firmware require WMM workaround which is very, very ugly to fix (even with LLM assisted, or savior claude fable, and gain is small) |
| **CPU** | Octa-core (1×3.19 GHz Cortex-X2 + 3×2.75 GHz Cortex-A710 + 4×1.80 GHz Cortex-A510) |
| **GPU** | Adreno 730 as Freedreno 725 (`0x07030002`). [Reference](https://raw.githubusercontent.com/termux/termux-packages/f8013fe24f/packages/mesa/0016-unofficial_support_adreno_710_720_722.patch) |
| **Display** | 30/60/120/144 Hz reported correctly. VRR from ~48 Hz up to 144 Hz. 30 Hz is supported in hardware, but Lenovo never set `mdss-dsi-qsync-min-refresh-rate` to 30, so the default floor is currently 48 Hz. [Reference](https://github.com/lolipuru/kernel_lenovo_sm8475-devicetrees/blob/lineage-24.0/qcom/display/display/cape-sde-display-common.dtsi) |
| **microSD** | Tested with SanDisk Ultra (A1) (mount under `/mnt/microSD` to avoid name conflict with external drive with same name), speed is vary, not gonnna grab all of them and do benchmark for sure |
| **Touch** | Novatek NT36523n — upstream + device-specific changes, touch gestures is temporary on halt (the tricky part is `game_mode` is conflict with pen mode (palm rejection), so touch gestures kernel is temporary on halt until i finish pen side) |
| **Fuel gauge** | battery report is now working properly with `power_now` and `µAh unit` implement (lenovo firmware only answer `power_now` with state of charge (measure with Current × Voltage) SC8280XP on lenovo sm8475 use µAh instead of mAh) |
| **Camera** | ROW and PRC ship different modules. This tree targets the ROW set (`ov13b10`, `s5k4h7`, `sc202cs`) PRC use `hi1339` as main camera and `gc02m1` for NEC (need confirmation for NEC), camera flash is now support (`pm8350c_flash`). |
| **USB** | Working, including host mode, DP-alt, DP-alt audio, and dual-port arbitration. usb on y700 (pretty much all generations) have usb port priority, more info on [port priority](/docs/port_priority.md) + onsemi FSA4480 type c port switch also working, now NCM is supported as well|
| **UFS** | Samsung KLUEG4RHGB, shifting between `HS-GEAR` 1 <> 4 with Rate B |
| **Iris (VPU)** | Hardware accelerated on V4L2. VA-API needs [qcom-va-driver](https://github.com/radxa-pkg/qcom-va-driver) |
| **Haptics** | AW86927 — upstream + small dual-haptics changes. rootfs only shipped 7 SRAM firmwares; other 131 haptics firmware are now working, and optional (you must ship firmware yourself) delay is vary between 1ms <> 5ms mesaure by median latency (4 i2c transfers) |
| **Sensors** | Auto-brightness (`STK3A5x-Ambient`), and Hall sensor (`BU52053NVX`) are only sensors implemented, Proximity (`STK3A5x`) and gyroscope (`BMI3X0`) are implemented but not exposed via iio, Pedometer and Magnetometer (`QMC630x`) are not implemented* (due to very few usages on these sensors, unless there's really usecase on linux), CDSP / SDSP / ADSP are working. *if there's usecase that need these sensors, i'd be happy to implement it, what you gonna do with proximity and gyroscope is up to you, i just enabled it. |
| **Suspend** | Works via normal sleep + power button. s2idle / deep, both are now working (current rootfs changes deep sleep drain is ~13.7 mA / 0.31%/hr) currently ADSP keep waking up CX and DDR. (basically +12,946 entries or basically ~2.4x per fucking second) |
| **Charging** | base charging code is using upstream code, with bypass charging (`pmic-glink` ported from SM8550, Lenovo supply props from NEC kernel source) |
| **Thermal** | Working. Power profiles included, 8 ADC thermistor are now implemented (`pmk8350_die_temp`, `pm8350_die_temp`, `pm8350_msm_therm`, `pm8350_cam_flash_therm`, `pm8350_hot_pocket_therm`, `pm8350_wide_rfc_therm`, `pm8350_chg_therm2`, `pm8350_usb1_conn_ts_ntc`,) temperature report is more or less accurated compare to zui (for example: `pm8350_chg_therm2` on mainline is 38.3 °C vs 37.8 °C on stock. many factor affect the report, so take it with gain of salt) |

## What doesn’t work / TO-DO

| Component | Notes |
| --- | --- |
| **HDR** | External monitor (DHI-PM19-S201S) doesn’t support HDR. Internal panel HDR is now supported (require dummy EDID for each WMs) |
| **AV1** | Software only. Qualcomm only started hardware AV1 on SM8550 and later — middle finger from qcom |
| **Stylus** | AP500U / AP501U (`Picasso`). which i don’t have (AP501U should arrives monday or tuesday), initial support is already on kernel. |
| **Modem** | this tablet doesn't have modem, you can't add something that doesn't have on first place. |
| **GPS** | this tablet doesn't have gps antenna, so don't bring it for hiking or camping, use compass, or your phone. |
| **NFC** | this tablet doesn't have nfc, so don't touch your card on it |

## Technical notes
| Component | Notes |
| --- | --- |
| **WIFI** | ath11k have D3cold failure which is unique to lenovo (lmao), so 2s firmware reload after suspend is normal (don't worry, it's automatic), WoW policy won't works there [Reference](https://lore-kernel.gnuweeb.org/ath11k/0fbb0b6e-c849-4e26-9c46-2ac4986f6b52@hauke-m.de/t/) |
| **Browser** | Youtube ambient mode breaks zero-copy video path due to YUV have to be convert and copied into an RGBA canvas, (not only that, it break cross-fade, so vrr never works it'll keep force render at 144hz) fixable, but will break many aspects. (2.8w (HDR), 2.71w (SDR) vs 33w (up to 35w with hdr) battery usage with ambient mode enabled)|
| **Waydroid** | I highly, highly recommend to compile it yourself if you want to run waydroid on linux |
| **Persist** | healthy persist partition is required for hardware functional on mainline linux, **DO NOT** boot this rootfs if your persist is corrupted, or broken, if you're on zui **ALWAYS** backup clean persist, you **CAN'T** borrow it from someone else (sure corrupted persist can still boots, but i won't **guarantee** hardware functionally) |

## Relock bootloader

I highly, highly **not recommend** you to do this or follow this section, however if you think it's good idea to relock bootloader (which giving you zero benefit), then i won't stop you.

this tablet uses [AVBv2](https://android.googlesource.com/platform/external/avb/+/master/README.md) with avb-custom-keys support

**Requirements**

- ability to read and think carefully
- Actual knowledge of AOSP build systems
- Understand how AVBv2 works
- Know How to sign images with your own private key

**Warning**

- ZUI is **NOT** support for relock bootloader, don't even dare trying it
- **BACKUP** sn.img, persist.img and devinfo.img first (these 3 images are very important, one is serial number information (if it gone, you're fucked) persist contain sensors calibration and others data, third is device info, but better backup at first place). if thing went wrong, i'll take 0 responsible.
- once you do this, you **must** sign images everytime you update kernel, are you sure you want to do this?
- LineageOS is recommend target to relock bootloader, however, just pick whatever AOSP you like (PixelOS, EvolutionX or whatever.)
- if you're using [armada os](https://github.com/armada-os/armada), or any distro that require to modified ABL **DO NOT** relock the bootloader
- Relock bootloader will make your data disappear like a magic, backup first
- if you're using ROW and any firmware that newer than 17.0.339 **DO NOT** relock the bootloader (AvbRSAPublicKey embedded in ABL make it risker to relock bootloader, [Source](https://miner7222.github.io/ltbox/en/index.html#supported-devices)), PRC? congratulations. you can relock pretty much almost all firmware versions

TO-DO, i didn't want some users report with bricked tablet, the relock document will fully write once i done with pen bringup

## Dual booting

doable, with some caveats.

- ZUI* only take slots A, you can repartition userdata and use boot, dtbo and vendor_boot into slot b
- if you want to dual boot with other OS like lineage, Crdroid or whatever you want, must be installed with fastboot packages
- if you want triple booting (eg: with unixnu or mu-silicium), you must use another method or find way to boot over sdcard

## How does it works?

1. first, ZUI guarantee to booted on slot A according to rawprogram.xml (EDL restore don't care if you're on A or B, it care on partition sectors, start and end byte)

2. on custom rom (LineageOS, Crdroid or AOSP based rom), recovery zip (eg: zip that contain payload.bin) will always flashed on inactive slot (eg: A > B, B > A due to how [virtual A/B](https://source.android.com/docs/core/ota/virtual_ab) Works), so when you're building AOSP, do `mka updatepackages` then flash it on fastboot or fastbootd (`fastboot update *.zip`) so it'll not override inactive slot

3. userdata repartition is still requires (repartition will require to format data, so backup first), or use microSD if space is limited (i'd recommend microSD that usable on nintendo switch (eg: sandisk ultra, or sandisk extreme or uhs-iii card), but still, booting full OS on microSD card is **not recommend**)

Notes:
1. if you're using zui as main OS, be careful as some firmware, booting to B guarantee to get you into brazil (EDL)

2. if you fucked up, to reach EDL, do `fastboot oem edl` or plug usb cable on long port while pressing volume up to reach EDL, then use QFIL (PRC) or use lenovo software fix (ROW) to restore

3. actually, there's some case where when you edl restore, it'll leave some linux image flashed on opposite slot, so always double check before you relock bootloader on zui

4. **DO NOT, EVER, MODIFY ABL UNLESS YOU KNOW WHAT ARE YOU DOING**

## Issues report and AI policy

- i **don't** give a fuck on AI involved as this start as personal project.
- however, any report that use LLM assisted must be test and validated from user first, and must be able to answer my question if i doubt on the methods, any issue or PR with LLM assisted straight from ass without test and validated from user **will be closed immediately** 

## License
Original code and scripts developed for this project are licensed under the GNU General Public License version 2.0 only (GPL-2.0-only), unless otherwise specified.

See LICENSE for the full GPL-2.0 license text.

Firmware provided by Qualcomm and Lenovo is proprietary and is not covered by this project's GPL-2.0 license.

All rights to such firmware remain with their respective copyright holders. These firmware files are subject to their original licensing and redistribution terms.

This project does not claim ownership of any proprietary firmware.
