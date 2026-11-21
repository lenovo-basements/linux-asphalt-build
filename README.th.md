# Rootfs build script for lenovo y700 gen 2

<p align="center">
  <img width="1051" height="657" alt="image" src="https://github.com/user-attachments/assets/6bbcf9a0-ddd8-4c07-b14d-f9828ae97f9e" />
  <img width="1051" height="657" alt="image" src="https://github.com/user-attachments/assets/d335d65b-66d6-4138-8bd4-7c8437d3622a" />
</p>

<p align="center"> <a href="https://www.pixiv.net/en/artworks/151930453">wallpaper</a></p>

<p align="center"><a href="/README.md">English</a> | ภาษาไทย</p>

---

## Descriptions
สคริปต์ กับ rootfs สำหรับ **Arch Linux ARM** บน
**Lenovo Legion Y700 (2023)** — โมเดล `TB320FC`, โค้ดเนม `asphalt`.

## Disclaimer
- โปรเจคนี้ใช้เคอร์เนลจาก [torvalds/linux](https://github.com/torvalds/linux). ไม่ต้องไปคาดหวังว่ามันจะเสถียร เพราะมันมีสิทธิ์ปังปินาศตอนไหนก็ได้ แล้วแต่ว่า merge มันจะเยอะขนาดไหน
- บอกก่อนว่า กู **ไม่** รับผิดชอบอะไรทั้งนั้นถ้าหากอยู่ดีๆแท็บเล็ตมันจะมีปัญหา กล้องใช้ไม่ได้ คุยกับหัวหน้าไม่ได้ ถ้าโดนไล่ออกแล้วมาโทษกู กูจะขำกลิ้งให้ดู
- rootfs อันนั้นมีแค่ส่วนที่จำเป็นเท่านั้น หาวิธี compile dependencies เอาเอง
- ไม่ submit ขึ้น LKML แค่ android ก็ปวดหัวจะตายห่าแล้ว เพราะงั้น maintain ไปเรื่อยๆนั่นแหล่ะ พอ
- คืออันนี้ทำมาไว้ให้ตัวเองอ่าน eroge เฉยๆ ถ้าจะให้ปรับแต่งเกมมิ่งอะ ไม่ไหว ขี้เกียจ + ไม่ใช่ target.
- จำไว้ว่า rootfs นี้ทำมาเป็นแค่ฐาน เอาแค่ core ฟังก์ชั่นหลักให้มันแข็งแรงพอที่คนอื่นจะเอาไปทำเชี่ยอะไรก็ได้

## Resources

- [Kernel source](https://github.com/lenovo-basements/lenovo-sm8475-mainline)
- [Firmware repo](https://github.com/lenovo-basements/asphalt-firmware)
- [What’s working](#whats-working)
- [Build instructions](scripts/README.md) (ไม่มีภาษาไทย ขี้เกียจเขียน)
- [Relock bootloader](#relock-bootloader)
- <a href="/docs/camera.th.md">แชท อยากระบายเรื่องกล้องรุ่นนี้ว่ะ</a>

## What’s working

| Component | Notes |
| --- | --- |
| **เสียง** | รุ่นนี้ใช้ Cirrus Logic CS35L45, ใช้โค้ดผ่าน upstream แทน เพราะมันมีอยู่แล้ว ที่เหลือก็เบสิก linux (`ALSA + UCM`) แต่แนะนำให้จูนเอง ใช้ `EasyEffects` เพราะลำโพงแม่งกากฉิบหาย|
| **ไวไฟ / บลูทูธ** | WCN6855, ใช้โค้ดผ่าน upstream เหมือนกัน (เฟิร์มแวร์ใช้ของ xiaomi pad 6 pro (`OS3.0.7.0.VMYCNXM`) เพราะของ lenovo ต้องแก้บัค WMM ซึ่งมันไม่คุ้ม ต่อจะให้ใช้ claude fable ก็เถอะ ไม่คุ้ม เอาโทเคนไปทำอย่างอื่นดีกว่า) |
| **CPU** | Octa-core (1×3.19 GHz Cortex-X2 + 3×2.75 GHz Cortex-A710 + 4×1.80 GHz Cortex-A510) |
| **GPU** | Adreno 730 แต่ Freedreno โชว์เป็น FD725 (`0x07030002`) แทน. [Reference](https://raw.githubusercontent.com/termux/termux-packages/f8013fe24f/packages/mesa/0016-unofficial_support_adreno_710_720_722.patch) |
| **จอภาพ** | 30/60/120/144 Hz ใช้ได้หมดนะ. VRR ก็ได้ตั้งแต่ ~48 Hz ลากยาวถึง 144 Hz. จริงๆ 30 Hz มันรับนะ แต่ Lenovo ไม่ได้ตั้ง `mdss-dsi-qsync-min-refresh-rate` ไว้ มันเลยได้แค่ 48hz นั่นแหล่ะ [Reference](https://github.com/lolipuru/kernel_lenovo_sm8475-devicetrees/blob/lineage-24.0/qcom/display/display/cape-sde-display-common.dtsi), vrr ใช้ใน stylus ไม่ได้ ในรอมศูนย์มันก็ใช้ไม่ได้เหมือนกัน |
| **microSD** | ความเร็วไม่ได้แย่นะ ลองกับ SanDisk Ultra (A1) มันก็พอได้อยู่อะ (mount ในชื่อ `microSD` เพราะกันปัญหาชื่อซํ้า) ส่วนความเร็วก็แล้วแต่ machine god จะประทานพร |
| **ทัชสกรีน** | Novatek NT36523n — upstream + โค้ดฝั่ง lenovo นิดหน่อย สำหรับสไตลัส |
| **Fuel gauge** | ตอนนี้รีพอร์ตถูกต้อง 100% (เฟิร์มแวร์ lenovo แม่งรีพอร์ต `power_now` เป็น state of charge, วัดจาก Current × Voltage) ของแถมคือ SC8280XP แม่งก็รีพอร์ตเป็น µAh แทนที่จะเป็น mAh |
| **กล้อง** | ROW กับ PRC ใช้กล้องคนละชุดกัน อันนี้ของ ROW (`ov13b10`, `s5k4h7`, `sc202cs`) ถ้าใช้ NEC (เครื่องญี่ปุ่น)... โชคดี bro (เพราะใช้ `gc02m1` เป็น marco) ถ้าใช้เครื่อง PRC ก็โชคดีเช่นกัน กล้องแม่งคนละตัวเลย (`hi1339` ในเลนส์หลัก), flash ใช้ได้แล้วจา (`pm8350c_flash`)|
| **USB** | ใช้ได้หมดทั้ง 2 พอร์ตอะ รวมถึงต่ออกจอได้ y700 ทุกรุ่นใน้ usb แบบ priority หมด อันนี้อธิบายแยก [ที่นี่](/docs/port_priority.th.md), host mode กับ NCM ตอนนี้ก็ใส่มาให้ละ |
| **UFS** | Samsung KLUEG4RHGB, HS-GEAR 1 <> 4 วิ่งไปมาราวๆนี้แหล่ะ ใช้ได้ปกติละ |
| **Iris (VPU)** | ผ่าน V4L2. ถ้าจะใช้ VA-API (มึงใช้ brave) ต้องใช้ [qcom-va-driver](https://github.com/radxa-pkg/qcom-va-driver) แทน |
| **มอเตอร์สั่น** | AW86927 — ใช้ upstream + โค้ดจาก lenovo นิดหน่อย ไม่ง้ันมันไม่ออกสองฝั่ง, ที่ใส่ให้มี 7 ตัว, อีก 131 ที่เหลือเป็นของแถม (วัดดีเลย์อยู่ประมาณ 1 - 5ms, ใช้ค่ามัธยฐานของเวลาหน่วงเป็นตัววัด)|
| **เซ็นเซอร์** | ปรับแสงอัตโนมัติ, เอาเคสปิดให้หลับ, ไจโร. CDSP / SDSP / ADSP เวิร์คหมด |
| **Sensors** | มีแค่ปรับแสงอัตโนมัติ (`STK3A5x-Ambient`), กับฮอลล์เซ็นเซอร์ (`BU52053NVX`) ทื่ใส่มา, ไจโรสโคป (`BMI3X0`) กับ Proximity (`STK3A5x`) ใส่มา แต่ไปเปิดเองเอง ส่วน Pedometer กับ Magnetometer (`QMC630x`) ไม่ได้ใส่มา เพราะไม่รู้จะใส่มาทำไม*, ส่วน CDSP / SDSP / ADSP พวกนี้เวิร์คหมด. *แต่ถ้ามีใครต้องใช้ก็บอก ยินดีจะใส่มาให้ แต่ตอนนี้หาเหตุผลไม่ได้จริงๆ :P ส่วน proximity กับ gyroscope ใครอยากเปิดก็เปิด ใส่มาให้แล้ว |
| **Suspend** | ได้หมดทั้งปล่อยให้หลับเอง กับใช้ปุ่มให้มันหลับ. s2idle / deep อยากได้แบบไหนไปเลือกเอาเอง (ปล่อยยิงยาว 5 ชั่วโมงได้ `apss`: 100%, `aosd`/`cxsd`/`ddr`: 99.9%, `adsp`: 100%, `slpi`/`slpi_island`: 100% กับ `cdsp`: 100%, กินแบตราวๆ `0.19%/hr` (หรือ `< 8.2 mA` ในแบตที่ชาร์จที่ `4341 mAh`) โดยประมาณ, ตัวเลขนี้ใช้เพื่อการโฆษณาเท่านั้น.) |
| **ระบบชาร์จ** | Bypass charging ใช้ได้ แต่ไม่ 100% เท่ารอมศูนย์ (`pmic-glink` พอร์ตจาก SM8550, กับใช้โค้ด Lenovo จากเคอร์เนล NEC) |
| **ระบบความร้อน** | ใช้ได้ เล่นเกมได้อยู่ มี power profiles แถมไปให้, ADC thermistor มี 8 ตัว ใส่มาให้แล้วเอาไว้เช็คความร้อนต่อจุด (`pmk8350_die_temp`, `pm8350_die_temp`, `pm8350_msm_therm`, `pm8350_cam_flash_therm`, `pm8350_hot_pocket_therm`, `pm8350_wide_rfc_therm`, `pm8350_chg_therm2`, `pm8350_usb1_conn_ts_ntc`,) ถามว่าแม่นมั้ย มันก็พอวัดเบื้องต้นได้อะ (อย่าง `pm8350_chg_therm2` ใน mainline มัน 38.3 °C ต่างจาก zui ที่บอกราวๆ 37.8 °C เพราะงั้นไว้เช็คเบื้องต้นดีกว่า) |

## What doesn’t work / TO-DO

| Component | Notes |
| --- | --- |
| **HDR** | จอนอกที่มีไม่รับ HDR (DHI-PM19-S201S) จอในใช้ได้หมด แต่ต้องใช้ dummy EDID เท่านั้น |
| **AV1** | ไปด่า qcom ว่าทำไมมึงไม่ใส่ hardware acceleration มาให้ เพราะงั้นอย่าหาเปิด AV1 เด็ดขาด |
| **Stylus** | AP500U / AP501U (Picasso). ใส่มาแล้ว เหลือแค่ส่วน userspace ที่ต้องเพิ่มหน่อย (วัดแรงกดกับองศาปากกามันแล้วแต่แอปไง คงไปโฟกัสกับพวก bluez หรือลูกเล่นที่เหลือดีกว่า) |
| **Modem** | แท็บเล็ตนี้มันไม่มีโมเด็ม เปิดยังไงมันก็ไม่มา เหมือนแฟนเก่าที่จากไป. |
| **GPS** | แท็บเล็ตนี้ไม่มี GPS ถ้าจะเดินป่าแนะนำให้ใช้มือถือ ไม่ก็เข็มทิศ. |
| **NFC** | แท็บเล็ตมันไม่มี NFC ว้อย ไม่ต้องเอาไปแตะ true wallet ที่เซเว่น |
| **Gestures** | ใส่มาหมดละ ทั้ง `DT2W`, `pen_mode`, `game_mode`, `panel orientation` |

## Technical notes
| Component | Notes |
| --- | --- |
| **WIFI** | ath11k เจอปัญหา D3cold พัง แล้วเป็นแค่กับ lenovo ด้วยนะ ไปอ่านเอาใน [Reference](https://lore-kernel.gnuweeb.org/ath11k/0fbb0b6e-c849-4e26-9c46-2ac4986f6b52@hauke-m.de/t/) เพราะรายละเอียดมันหนามาก (firmware มันรีโหลดเองตลอด อย่าไปคิดไรเยอะ)|
| **Browser** | youtube ambient mode แม่งส้นตีนมากๆ แม่งทำ zero-copy พังหมด (YUV มันต้องแปลงแล้วก็คัดไป RGBA canvas cross-fade มันเลยพัง เพราะงั้นมันเลย render ที่่ 144hz อย่างเดียว VRR มันใช้ไม่ได้) อย่าหาเปิดเชียว นอกจากจะต่อจอนอก (เทสแล้ว 2.71w (SDR) / 2.8 (HDR) ถ้าไม่ได้เปิด แต่ถ้าเปิด หวานเจี๊ยบ กินไปเต็มๆ 33w (บางทีก็ 35w) |
| **Persist** | ถ้าจะบู๊ต mainline linux persist ต้องไม่พัง **ห้าม** บู๊ต rootfs เด็ดขาดถ้า persist พัง, ถ้าเกิดอยู่ในรอมศูนย์ **สำรอง** persist ก่อน, ถ้าพัง **มึงไม่สามารถยืม persist จากคนอื่นได้** (คือจะบู๊ตก็ได้ แต่ถ้ามีปัญหาคือมา ไม่รับประกันเรื่องความเสถียร, และไม่รับ issues tracking นะ) |
| **Waydroid** | แนะนำให้ build เอง กราบเลย build เองเถอะ ใช้ AI ช่วยหรืออะไรก็ได้แต่ช่วย build เองเถอะ ขอร้อง แต่ถ้าขี้เกียจจริงๆ `sudo pacman -S waydroid` แต่จะได้แค่ android 13, เลือกเอา|

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

