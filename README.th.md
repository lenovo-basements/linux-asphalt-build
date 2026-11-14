# Rootfs build script for lenovo y700 gen 2

<p align="center"><a href="/README.md">English</a> | ภาษาไทย</p>

---

## Descriptions
สคริปต์ กับ rootfs สำหรับ **Arch Linux ARM** บน
**Lenovo Legion Y700 (2023)** — โมเดล `TB320FC`, โค้ดเนม `asphalt`.

ปล. จะแทน arch ด้วย gentoo, แต่จะปราณีให้โดยการใส่ nixos มาให้

## Disclaimer
- โปรเจคนี้ใช้เคอร์เนลจาก [torvalds/linux](https://github.com/torvalds/linux). ไม่ต้องไปคาดหวังว่ามันจะเสถียร เพราะมันมีสิทธิ์ปังปินาศตอนไหนก็ได้ แล้วแต่ว่า merge มันจะเยอะขนาดไหน
- บอกก่อนว่า กู **ไม่** รับผิดชอบอะไรทั้งนั้นถ้าหากอยู่ดีๆแท็บเล็ตมันจะมีปัญหา กล้องใช้ไม่ได้ คุยกับหัวหน้าไม่ได้ ถ้าโดนไล่ออกแล้วมาโทษกู กูจะขำกลิ้งให้ดู
- rootfs อันนั้นมีแค่ส่วนที่จำเป็นเท่านั้น หาวิธี compile dependencies เอาเอง
- ไม่ submit ขึ้น LKML แค่ android ก็ปวดหัวจะตายห่าแล้ว เพราะงั้น maintain ไปเรื่อยๆนั่นแหล่ะ พอ

## Resources

- [Kernel source](https://github.com/lenovo-basements/lenovo-sm8475-mainline)
- [Firmware repo](https://github.com/lenovo-basements/asphalt-firmware)
- [What’s working](#whats-working)
- [Building (kernel + packaging)](scripts/kernel/README.md) (ไม่มีภาษาไทย ขี้เกียจเขียน)
- [Relock bootloader](#relock-bootloader)
- <a href="/docs/camera.th.md">แชท อยากระบายเรื่องกล้องรุ่นนี้ว่ะ</a>

## What’s working

| Component | Notes |
| --- | --- |
| **เสียง** | รุ่นนี้ใช้ Cirrus Logic CS35L45, ใช้โค้ดผ่าน upstream แทน เพราะมันมีอยู่แล้ว|
| **ไวไฟ / บลูทูธ** | WCN6855, ใช้โค้ดผ่าน upstream เหมือนกัน |
| **CPU** | Octa-core (1×3.19 GHz Cortex-X2 + 3×2.75 GHz Cortex-A710 + 4×1.80 GHz Cortex-A510) |
| **GPU** | Adreno 730 แต่ Freedreno โชว์เป็น FD725 (`0x07030002`) แทน. [Reference](https://raw.githubusercontent.com/termux/termux-packages/f8013fe24f/packages/mesa/0016-unofficial_support_adreno_710_720_722.patch) |
| **จอภาพ** | 30/60/120/144 Hz ใช้ได้หมดนะ. VRR ก็ได้ตั้งแต่ ~48 Hz ลากยาวถึง 144 Hz. จริงๆ 30 Hz มันรับนะ แต่ Lenovo ไม่ได้ตั้ง `mdss-dsi-qsync-min-refresh-rate` ไว้ มันเลยได้แค่ 48hz นั่นแหล่ะ [Reference](https://github.com/lolipuru/kernel_lenovo_sm8475-devicetrees/blob/lineage-24.0/qcom/display/display/cape-sde-display-common.dtsi) |
| **microSD** | ความเร็วไม่ได้แย่นะ ลองกับ SanDisk Ultra (A1) มันก็พอได้อยู่อะ|
| **ทัชสกรีน** | Novatek NT36523n — upstream + โค้ดฝั่ง lenovo นิดหน่อย สำหรับสไตลัส |
| **Fuel gauge** | ตอนนี้รีพอร์ตถูกต้อง 100% (เฟิร์มแวร์ lenovo แม่งรีพอร์ต `power_now` เป็น state of charge, วัดจาก Current × Voltage) ของแถมคือ SC8280XP แม่งก็รีพอร์ตเป็น µAh แทนที่จะเป็น mAh |
| **กล้อง** | ROW กับ PRC ใช้กล้องคนละชุดกัน อันนี้ของ ROW (`ov13b10`, `s5k4h7`, `sc202cs`) ถ้าใช้ NEC (เครื่องญี่ปุ่น)... โชคดี bro (เพราะใช้ `gc02m1` เป็น marco) ถ้าใช้เครื่อง PRC ก็โชคดีเช่นกัน กล้องแม่งคนละตัวเลย (`hi1339` ในเลนส์หลัก) |
| **USB** | ใช้ได้หมดทั้ง 2 พอร์ตอะ รวมถึงต่ออกจอได้ y700 ทุกรุ่นใน้ usb แบบ priority หมด อันนี้อธิบายแยก [ที่นี่](/docs/port_priority.th.md) |
| **UFS** | ใช้ได้ ติดแค่มันสุดได้แค่ HS-GEAR4 (Rate A) เพราะ UFS มันได้แค่นี้ ทำไงได้ |
| **Iris (VPU)** | ผ่าน V4L2. ถ้าจะใช้ VA-API (มึงใช้ brave) ต้องใช้ [qcom-va-driver](https://github.com/radxa-pkg/qcom-va-driver) แทน |
| **มอเตอร์สั่น** | AW86927 — ใช้ upstream + โค้ดจาก lenovo นิดหน่อย ไม่ง้ันมันไม่ออกสองฝั่ง, ที่ใส่ให้มี 7 ตัว, อีก 131 ที่เหลือเป็นของแถม (วัดดีเลย์อยู่ประมาณ 1 - 5ms, ใช้ค่ามัธยฐานของเวลาหน่วงเป็นตัววัด)|
| **เซ็นเซอร์** | ปรับแสงอัตโนมัติ, เอาเคสปิดให้หลับ, ไจโร. CDSP / SDSP / ADSP เวิร์คหมด |
| **Suspend** | ได้หมดทั้งปล่อยให้หลับเอง กับใช้ปุ่มให้มันหลับ. s2idle / deep อยากได้แบบไหนไปเลือกเอาเอง|
| **ระบบชาร์จ** | Bypass charging ใช้ได้ แต่ไม่ 100% เท่ารอมศูนย์ (`pmic-glink` พอร์ตจาก SM8550, กับใช้โค้ด Lenovo จากเคอร์เนล NEC) |
| **ระบบความร้อน** | ใช้ได้ เล่นเกมได้อยู่ มี power profiles แถมไปให้ |

## What doesn’t work / TO-DO

| Component | Notes |
| --- | --- |
| **HDR** | จอนอกที่มีไม่รับ HDR (DHI-PM19-S201S) จอในใช้ได้แค่ใน hyprland ก่อน เดี๋ยว kde กับ gnome ตามมาทีหลัง |
| **AV1** | ไปด่า qcom ว่าทำไมมึงไม่ใส่ hardware acceleration มาให้ เพราะงั้นอย่าหาเปิด AV1 เด็ดขาด |
| **Stylus** | AP500U / AP501U / Precision Pen 2. ไม่มีติดตัวสักอัน เลยซัพพอร์ตไม่ได้ (ถ้าไม่มีไรติดขัด จันทร์ไม่ก็อังคารนี้น่าจะเริ่มละ) |

## Technical notes
| Component | Notes |
| --- | --- |
| **WIFI** | ath11k เจอปัญหา D3cold พัง แล้วเป็นแค่กับ lenovo ด้วยนะ ไปอ่านเอาใน [Reference](https://lore-kernel.gnuweeb.org/ath11k/0fbb0b6e-c849-4e26-9c46-2ac4986f6b52@hauke-m.de/t/) เพราะรายละเอียดมันหนามาก|
| **Browser** | youtube ambient mode แม่งส้นตีนมากๆ แม่งทำ zero-copy พังหมด (YUV มันต้องแปลงแล้วก็คัดไป RGBA canvas cross-fade มันเลยพัง เพราะงั้นมันเลย render ที่่ 144hz อย่างเดียว VRR มันใช้ไม่ได้) อย่าหาเปิดเชียว นอกจากจะต่อจอนอก (เทสแล้ว 2.71w (SDR) / 2.8 (HDR) ถ้าไม่ได้เปิด แต่ถ้าเปิด หวานเจี๊ยบ กินไปเต็มๆ 33w (บางทีก็ 35w) |

## Relock bootloader

อยากจะบอกว่า **อย่าหาทำ** นอกจากว่าถ้าคิดแล้วว่าอยากล็อค ด้วยเหตุผลอะไร 108 ก็แล้วแต่ แต่ถ้าคิดจะล็อค คุณมาถูกทางแล้ว ไกด์นี้จะบอกวิธีว่าจะล็อคยังไงไม่ให้เสียเวลาโหลดไฟล์ EDL

แท็บเล็ตนี้ใช้ [AVBv2](https://android.googlesource.com/platform/external/avb/+/master/README.md) คู่กับ avb-custom-keys

**Requirements**

- ความสามารถในการอ่านเกิน 7 บรรทัด
- ต้องรู้ว่า build AOSP ยังไง
- เข้าใจว่า AVBv2 มันทำงานยังไง
- ต้องรู้ว่าจะ sign images ด้วย private key ตัวเองยังไง

**Warning**

- ZUI ไม่รองรับทุกกรณี ถ้าล็อค รับผิดชอบตัวเอง
- **แบ็คอัพ** sn.img, persist.img and devinfo.img ก่อน (สามอันนี้สำคัญมาก อันนึงเป็น serial number ใช้คู่กับ zui + restore tool, อันนึงเป็น calibration แทบจะทุกอย่าง อีกอัน ไม่รู้แบ็คอัพไว้ทำไม แต่มันบอกรายละเอียดเครื่อง) ถ้ามันพัง หรือหาย ถือว่าเตือนแล้ว
- lock เมื่อไหร่, sign image ทุกรอบที่อัพเดต เพราะงั้นถามใจตัวเองว่าอยากจะทำหรือเปล่า
- แนะนำให้ใช้ LineageOS แต่ อยากใช้อะไรก็ใช้ Evox, pixelos หรือเชี่ยไรก็ได้ ขอแค่เป็น AOSP พอ 
- ถ้ามีแพลนจะทำ [armada os](https://github.com/armada-os/armada), หรือ distro เจ้าไหนที่ต้องดัดแปลง abl **ห้ามล็อคเด็ดขาด**
- ล็อค bootloader ถือว่าข้อมูลของท่านจะหายไปเหมือนเวลาที่เขาหมดรัก เพราะงั้นแบ็คอัพก่อน
- (ROW) ถ้าใช้เฟิร์มแวร์ที่ใหม่กว่า 17.0.339 **อย่า** relock bootloader (AvbRSAPublicKey ที่ฝังมาใน ABL มันเสี่ยงเกินที่จะล็อค bootloader, [Source](https://miner7222.github.io/ltbox/en/index.html#supported-devices)), PRC? ยินดีด้วย แต่ยากกว่านิดนึง

TO-DO, ไม่อยากเจอพวก report แปลกๆ ไว้ก่อน เดี๋ยวมาเขียนต่อ

## Dual booting

ทำได้ แต่อย่าหาทำจะดีกว่า แต่ก็นะ ใครห้าม แต่มันมีเงื่อนไขอยู่

- ถ้าใช้ ZUI* ต้องใช้ slot B เท่านั้น เพราะ ZUI จะใช้ slot A เป็นหลัก
- ถ้าอยาก boot ไป os อื่น (พวก unixnu หรือ windows ผ่าน mu-silicium) แนะนำให้ถาม AI หาวิธี boot ผ่าน sdcard จะดีกว่า

## How does it works?

1. ZUI มันไม่เหมือนหวย มันลงล็อคที่ slot A เลย (ถ้าอิงตาม rawprogram.xml มันเช็คแค่ start/end sectors)

2. ถ้าจะใช้รอมโม อย่างพวก LineageOS, Crdroid อะไรพวกนี้ อย่าใช้ recovery zip (ดูง่ายๆก็ ถ้าแตกไฟล์มามี payload.bin นั่นแหล่ะ recovery) ไม่งั้นมันจะทับ slot ตรงข้าม (ตัวอย่างก็ A > B / B < A [ไปอ่านต่อในนี้](https://source.android.com/docs/core/ota/virtual_ab?hl=th)) เพราะงั้น ถ้า build เอง ให้ใช้ `mka updatepackages` แล้ว flash ตรงๆผ่าน fastboot (`fastboot update *.zip`)

3. userdata ยังไงก็ต้อง repartition (format data แน่นอน เพราะงั้นถ้าเกมเยอะ ไป backup ก่อน) ถ้าไม่งั้นก็ใช้ microSD card (แนะนำให้ใช้อันที่มันใช้กับ switch 1 / 2 ได้ ไม่ก็ UHS-III แต่มันแพง) แต่เอาจริงๆ อย่าหาทำเลย มันช้า

Notes:
1. บางเคส ถ้าจะ dualboot กับรอมศูนย์ ระวัง​ EDL ถามหาเพราะบางเวอร์ชั่น lenovo bootloader มันหลอน

2. ถ้าพลาด partition พัง พิมพ์ `fastboot oem edl` ใน fastboot หรือเสียบสาย usb ตรงช่องขวา (ไอที่มันเป็น 3.1) + เริ่งเสียงเพื่อเข้า EDL, แล้วใช้ QFIL (เครื่องจีน) ไม่ก็ lenovo software fix (เครื่องที่ไม่ใช่เครื่องจีนและญี่ปุ่น)

3. ถ้า restore แล้วอยาก relock เช็คว่า slot A/B มันเป็น ZUI หรือเปล่า เพราะมันมีเคสที่มัน flash แค่ slot เดียว เช็คก่อน relock นะเว้ย เดี๋ยวฉิบหาย

4. **หวังว่าจะไม่มีใคร modify ABL นะ หวังว่า อย่าทำเชียว**

## Issues report and AI policy

- ข้าพเจ้า **ไม่** แคร์ว่าท่านจะเป็น AI bro, เพราะอันนั้นมันเป็นโปรเจคส่วนตัว.
- แต่ถ้ามึงเขียน issues หรือเปิด PR โดยใช้ AI แล้วไม่เทสมาก่อน ตอบคำถามข้าพเจ้าไม่ได้ หรือมึงให้ AI เปิด PR/issues ข้าพเจ้า **ขอปิด PR/Issues นั้นๆ โดยไม่อ่านแม้แค่บรรทัดเดียว** 

## License
โค้ดที่ใส่เพิ่มมาทั้งหมดถือลิขสิทธิ์แบบ GPL-2.0-only, นอกจากจะโน๊ตไว้.
ดูที่ LICENSE สำหรับลิขสิทธิ์ GPL-2.0 แบบเต็ม.

เฟิร์มแวร์ที่จัดทำโดย Qualcomm และ Lenovo เป็นกรรมสิทธิ์และไม่อยู่ภายใต้ใบอนุญาต GPL-2.0 ของโครงการนี้
ลิขสิทธิ์ทั้งหมดของเฟิร์มแวร์ดังกล่าวเป็นของผู้ถือลิขสิทธิ์แต่ละราย เฟิร์มแวร์เหล่านี้อยู่ภายใต้ข้อกำหนดการอนุญาตและการแจกจ่ายซ้ำตามต้นฉบับ

โครงการนี้ไม่ได้อ้างสิทธิ์ความเป็นเจ้าของเฟิร์มแวร์ที่เป็นกรรมสิทธิ์ใดๆ

