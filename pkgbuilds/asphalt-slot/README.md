## Why qbootctl is really bad idea

**tl;dr qbootctl set_active_boot_slot() fucked up whole lun with single command**
**if this tool fucked you up, use software fix or QFIL to restore**

The problem is not switching the UFS boot LUN. On asphalt, ABL requires the boot LUN to follow the selected slot. Failing to switch it can cause the device to fall into fastboot instead of booting Android.

## What goes wrong with qbootctl

- Incomplete partition attribute swapping: qbootctl uses a PIN_SWAP_LIST covering 15 partition pairs, while asphalt has 28 GPT partition pairs. ABL updates the remaining pairs, potentially leaving a mixed firmware configuration.

- Inconsistent firmware state: Partitions such as aop_config, cpucp, shrm, uefi, dsp, imagefv, featenabler, uefisecapp, vendor_boot, recovery, and xbl_ramdump can remain associated with the wrong slot.

- Boot LUN corruption: The tested qbootctl slot-switching path has also resulted in the boot LUN being wiped, requiring recovery.

## How asphalt-slot differs

- asphalt-slot follows the slot-switching behavior expected by asphalt's bootloader:
- Updates the relevant slot attributes consistently.
- Selects the corresponding UFS boot LUN using bBootLunEn, writing only the required value (1 or 2).
- Keeps the boot LUN and selected firmware slot aligned.
- The boot LUN must follow the active slot. The problem with qbootctl is its incomplete partition swap and observed destructive behavior, not the LUN switch itself.
- Do not use qbootctl to change slots on asphalt, for god sakes.