# Camera

**Note**: this section of document is write by human, who spending 17 hours marathon to reverse engineer camera support even with LLM assisted for that

## why it's dogshit to impl

Y700 2nd gen use following camera sensors

- SC202CS (marco sensor) / GC02M1 (NEC)
- OV13B10 (Main) / Hi1339 (PRC)
- and Samsung S5K4H7

S5K4H7, OV13B10, Hi1339 are a bit hard, but drivers are well maintained and upstream, and easy to implement downstream code and submit to LKML later, if needed

however, the piece of dogshit that waste my time is SC202CS, why?

because the original code is pretty much dummy implementations 
the SC202CS have following spec as 

- fucking 134 init sequence address and data
- 01 / 00 as stream on / off
- 15 bit VTS, following by 

```
reg_fline & 0x7F00 >> 8 as 0x320e [6:0]
reg_fline & 0xFF as 0x320f [7:0]
```

- exposure as 16 bit, following by

```
reg_exposure >> 12 & 0x0F as 0x3e00 [3:0]
reg_exposure >> 4 & 0xFF as 0x3e01 [7:0]
reg_exposure << 4 & 0xF0 as 0x3e02 [7:4]
```

- then analogue gain following by

* 3e09 (00/01/03/07/0f = 1/2/4/8/16×) × fine 3e07 (0x80 = 1×) with following table
```
    { 1024,  0 },
    { 2048,  1 },
    { 4096,  3 },
    { 8192,  7 },
	{ 16384,  15 },
```

- *0x322e and 0x322f are unused (it's related to registor data for exposure upper limit, which lenovo didn't shipped here)

**also disclaimer**: no LLM involved on actual BSP source code, this data is obtain by kprobe on camera drivers and CCI debug log > author just do his job by translating it to something programmer or next LLM can understand

## Calibration data

well it's straightforward, from CamX tuning blob, but for now, camera calibration contain following table

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

CCM row, and no LSC implement for now, which will improve in future, if i'm not lazy