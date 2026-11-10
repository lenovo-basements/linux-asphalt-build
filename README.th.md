# Rootfs build script for lenovo y700 gen 2

<p align="center"><a href="/README.md">English</a> | ภาษาไทย</p>

---

## Descriptions
สคริปต์ กับ rootfs สำหรับ **Arch Linux ARM** บน
**Lenovo Legion Y700 (2023)** — โมเดล `TB320FC`, โค้ดเนม `asphalt`.

## Disclaimer
- โปรเจคนี้ใช้เคอร์เนลจาก [torvalds/linux](https://github.com/torvalds/linux). ไม่ต้องไปคาดหวังว่ามันจะเสถียร เพราะมันมีสิทธิ์ปังปินาศตอนไหนก็ได้ แล้วแต่ว่า merge มันจะเยอะขนาดไหน
- บอกก่อนว่า กู **ไม่** รับผิดชอบอะไรทั้งนั้นถ้าหากอยู่ดีๆแท็บเล็ตมันจะมีปัญหา กล้องใช้ไม่ได้ คุยกับหัวหน้าไม่ได้ ถ้าโดนไล่ออกแล้วมาโทษกู กูจะขำกลิ้งให้ดู
- rootfs อันนั้นมีแค่ส่วนที่จำเป็นเท่านั้น หาวิธี compile dependencies เอาเอง

## Resources

- [What’s working](#whats-working)
- [Building (kernel + packaging)](scripts/kernel/README.md) (ไม่มีภาษาไทย ขี้เกียจเขียน)
- [Relock bootloader](#relock-bootloader)

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
| **Fuel gauge** | พวก % แบตเตอรี่กับชาร์จเร็วใช้โค้ด upstream หมด, lenovo ใช้โค้ด qcom หมดเลยไม่ต้องอะไรเยอะ |
| **กล้อง** | ROW กับ PRC ใช้กล้องคนละชุดกัน อันนี้ของ ROW (`ov13b10`, `s5k4h7`, `sc202cs`) ถ้าใช้ PRC (เครื่องจีน)... โชคดี bro|
| **USB** | ใช้ได้หมดทั้ง 2 พอร์ตอะ รวมถึงต่ออกจอได้ (เหมือนรอมศูนย์เป๊ะ) |
| **UFS** | ใช้ได้ ติดแค่มันสุดได้แค่ HS-GEAR4 (Rate A) เพราะ UFS มันได้แค่นี้ ทำไงได้ |
| **Iris (VPU)** | ผ่าน V4L2. ถ้าจะใช้ VA-API (มึงใช้ brave) ต้องใช้ [qcom-va-driver](https://github.com/radxa-pkg/qcom-va-driver) แทน |
| **มอเตอร์สั่น** | AW86927 — ใช้ upstream + โค้ดจาก lenovo นิดหน่อย ไม่ง้ันมันไม่ออกสองฝั่ง เหลือแค่เอา effect 138 อันจากรอมศูนย์มายัดในนี้|
| **เซ็นเซอร์** | ปรับแสงอัตโนมัติ, เอาเคสปิดให้หลับ, ไจโร. CDSP / SDSP / ADSP เวิร์คหมด |
| **Suspend** | ได้หมดทั้งปล่อยให้หลับเอง กับใช้ปุ่มให้มันหลับ. **s2idle เท่านั้น** เพราะ RPMh ในกล้องมัน *** panic ทุกครั้งที่ขึ้น deep|
| **ระบบชาร์จ** | Bypass charging ใช้ได้ แต่ไม่ 100% เท่ารอมศูนย์ (`pmic-glink` พอร์ตจาก SM8550, กับใช้โค้ด Lenovo จากเคอร์เนล NEC) |
| **ระบบความร้อน** | ใช้ได้ เล่นเกมได้อยู่ มี power profiles แถมไปให้ |

## What doesn’t work / TO-DO

| Component | Notes |
| --- | --- |
| **HDR** | จอนอกที่มีไม่รับ HDR (DHI-PM19-S201S) จอในไว้ก่อน ขี้เกียจ |
| **AV1** | ไปด่า qcom ว่าทำไมมึงไม่ใส่ hardware acceleration มาให้ เพราะงั้นอย่าหาเปิด AV1 เด็ดขาด |
| **Stylus** | AP500U / AP501U / Precision Pen 2. ไม่มีติดตัวสักอัน เลยซัพพอร์ตไม่ได้ |

## Relock bootloader

มึงบ้าป่าวไอ้ชาย?

ทำได้ — เพราะแท็บเล็ตนี้มันใช้ AVBv2 คู่กับ avb-custom-keys แต่.... ใครจะห้ามได้

**Requirements**

- สมอง, กับความสามารถในการอ่านเกิน 7 บรรทัด
- ต้องรู้ว่า build AOSP ยังไง
- เข้าใจว่า AVBv2 มันทำงานยังไง
- ต้องรู้ว่าจะ sign images ด้วย private key ตัวเองยังไง

TO-DO, ไม่อยากเจอพวก report แปลกๆ ไว้ก่อน เดี๋ยวมาเขียนต่อ

## Issues report and AI policy

- ข้าพเจ้า **ไม่** แคร์ว่าท่านจะเป็น AI bro, เพราะอันนั้นมันเป็นโปรเจคส่วนตัว.
- แต่ถ้ามึงเขียน issues หรือเปิด PR โดยใช้ AI แล้วไม่เทสมาก่อน ตอบคำถามข้าพเจ้าไม่ได้ หรือมึงให้ AI เปิด PR/issues ข้าพเจ้า **ขอปิด PR/Issues นั้นๆ โดยไม่อ่านแม้แค่บรรทัดเดียว** 
