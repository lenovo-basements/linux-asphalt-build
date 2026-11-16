# Camera

**Note**: หัวข้อนี้ คนล้วนๆ ไม่มี AI ช่วยกรองคำ ใช้แค่ช่วยแกะ กับ 17 ชั่วโมงที่เสียไป เอาไปทำอย่างอื่นดีกว่า

## why it's dogshit to impl

Y700 เจนสองใช้กล้องหลายตัวฉิบหาย ตามนี้

- SC202CS (marco sensor) / GC02M1 (NEC)
- OV13B10 (Main) / Hi1339 (PRC)
- Samsung S5K4H7

S5K4H7, OV13B10, Hi1339 ยาก แต่ไดร์เวอร์มันมีคน maintain อยู่แล้ว แถมค่อนข้างโอเคด้วย

แต่ไอตัวปัญหาจริงๆมันคือ SC202CS, ทำไมอะหรอ

เพราะไดร์เวอร์ upstream มันแทบจะไม่มีเหื้ยอะไรเลยไง ถ้าเอาตามสเปค ก็

- 134 init sequence address and data
- 01 / 00 as stream on / off
- VTS อยู่ที่ 15 bit, โค้ดมันจะประมาณนี้

```
reg_fline & 0x7F00 >> 8 as 0x320e [6:0]
reg_fline & 0xFF as 0x320f [7:0]
```

- exposure อยู่ที่ 16 bit, ตามข้างล่าง

```
reg_exposure >> 12 & 0x0F as 0x3e00 [3:0]
reg_exposure >> 4 & 0xFF as 0x3e01 [7:0]
reg_exposure << 4 & 0xF0 as 0x3e02 [7:4]
```

- แล้วก็ analogue gain โค้ดมันจะประมาณ

* 3e09 (00/01/03/07/0f = 1/2/4/8/16×) × fine 3e07 (0x80 = 1×) ตามด้วยข้างล่างนี่
```
    { 1024,  0 },
    { 2048,  1 },
    { 4096,  3 },
    { 8192,  7 },
	{ 16384,  15 },
```

- *0x322e กับ 0x322f ส่วนนี้ไม่ได้ใช้ (มันเกี่ยวกับ exposure upper limit, ซึ่ง lenovo ไม่ได้เปิดไว้ (ดีแล้ว marco กล้องนี้แม่ง...)

**also disclaimer**: LLM ใช้แค่เก็บ data จาก kprobes debug เท่านั้น เรื่องเช็คเทียบกับ BSP คือหน้าที่คนเขียน แล้วเอามาเขียนใน documents อีกทีให้คนอื่นเขาอ่าน รู้เรื่องมั้ย ไม่รู้เหมือนกัน

## Calibration data

อันนี้ง่ายหน่อย, เอามาจาก CamX tuning blob ใน vendor, ตอนนี้ table มัน basic มีแค่นี้แหล่ะ

```
algorithms:
  - BlackLevel:
  - Awb:
  - Ccm:
      ccms:
        - ct: 3580
          ccm: [  2.1210, -1.3615,  0.2405,
                 -0.2392,  1.2840, -0.0448,
                 -0.1013, -0.8230,  1.9243 ]
        - ct: 4630
          ccm: [  1.9161, -1.1088,  0.1927,
                 -0.2137,  1.4293, -0.2156,
                 -0.0213, -0.6407,  1.6620 ]
        - ct: 5530
          ccm: [  1.9175, -1.0899,  0.1725,
                 -0.1279,  1.2718, -0.1439,
                  0.0296, -0.5280,  1.4984 ]
        - ct: 6810
          ccm: [  1.8280, -0.9319,  0.1039,
                 -0.1105,  1.3058, -0.1954,
                  0.0832, -0.4820,  1.3988 ]
  - Adjust:
  - Agc:
```

## Camera config shitfest

- OV13B10 ตั้งแต่แรกไว้ที่ DW9714, แต่พออดหลับอดนอนแล้วดูที่ com.qti.sensormodule.ofilm_ov13b10 ดีๆ, แม่งมันคือ `GT9768` นิหว่า, คือมันมี [upstream](https://lists.openwall.net/linux-kernel/2024/06/12/29) รับอยู่ละ, แต่บอกเลยว่าอันนี้คือฉิบหายข้อแรก. (ไฟล์ com.qti.sensormodule.ofilm_ov13b10 มันเซ็ต init ที่ `0x0c`, ตามด้วย `0x02`,`0x06`,`0x07` ทุกๆค่ามันจะ + ไปอีก `100 µs`)

- libcamera แม่งตั้ง long exposure ไว้แค่ 33.35ms, ผิดกับ ZuiCamera แล้วก็ lineage aperture แม่งตั้งอยู่ที่ 80ms, เพราะงั้นว่าทำไม [แพตช์นี้](https://github.com/lenovo-basements/linux-asphalt-build/blob/main/pkgbuilds/libcamera/0004-softisp-Allow-tuned-long-exposure.patch) ([อิงมาจาก upstream นี้](https://patchwork.libcamera.org/patch/28851/)) ถึงจำเป็น เพราะงั้น exposure จะได้ไม่ถึง 80ms เหมือน stock กับ aperture, เวลาตั้งค่าก็แค่ใส่ `max-exposure-time` ที่ 80ms อย่างน้อยมันก็ได้สีที่ดูดี แต่ก็ยังไม่ดีพอ.

- ฉิบหายข้อต่อมาคือ autofocus, จริงๆมันใช้ไม่ได้ด้วยจนรู้ว่าต้องตั้งเป็น GT9768 เนี่ยแหล่ะ, อย่างน้อยตอนนี้มันก็พอใช้ได้, มันตั้ง focus ราวๆ 460~512 (1920×1080, วัดด้วย snapshot กับ pirewire), [แพตช์นี้](https://github.com/lenovo-basements/linux-asphalt-build/blob/main/pkgbuilds/libcamera/0005-softisp-Add-tuned-contrast-autofocus.patch) สำคัญมาก เพราะ autofocus ต้องใช้, แต่ว่าตอนนี้คือยังล็อค AF บน snapsot ไม่ได้.... มั้ง?

- พวกสีพวกอะไรมันจะดีขึ้นเรื่อยๆ ถ้ามีเวลากับอดนอนมากพอ (ลองถ่ายในห้องมันราวๆ 168/170/166, แต่ถ้าถ่ายในที่แสงน้อยภาพมันจะเหลืองเหมือนเยี่ยว เหลืองแบบ เหลืองจริงๆ)
