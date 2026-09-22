# HARDWARE proof run — OpenOCD over HOSTIO4 on the real nanoSoC eth chiplet

**2026-09-22, 09:13-09:20 UTC**, host `srv03335`, board reached via `haps-dev`
(dongle `pico`, Waveshare RP2350, USB serial `e1b0aef0052ab176`, PMOD1).

> **This is the first time any of this has touched a board.** Every prior proof
> (six of them) ran against `adpmon.py` over TCP loopback with `adp-bridge --raw`.
> This run crossed the console-bridge translation layer that `--raw` turns off,
> which no proof had ever exercised.

**Result: steps 1-6 all PASSED. Every discriminator met. The board was left in
exactly the state it was found in (`verify-target` 7/7 before and after).**

`load_image` was deliberately NOT attempted, per the run brief. Block write was
left OFF throughout (`hostio4-bench.cfg:40` keeps it commented) and the driver
confirms `block write : off (W per word)` in every `hostio4_info` dump below.

---

## Binary used

`/home/dam1n19/SoCLabs/soclabs-openocd/build/openocd-src/src/openocd`
— the LOCAL build, `0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)`.

Checked before relying on it, as the brief required:

```
$ strings .../src/openocd | grep -c hostio4
200
$ .../src/openocd -c 'adapter list' -c 'exit' | grep hostio4
hostio4
```

The local binary was used rather than `haps-dev:/opt/soclabs-openocd/...` because
OpenOCD must run where the `adp-bridge` TCP port is, and the whole chain runs on
the workstation (`haps-hostio` does its own ssh remoting to `haps-dev`; see
`hostio4-bench.cfg` header). Only `hostio4` was needed; `ahb_qspi` was not
exercised and did not appear in `adapter list` on this binary.

---

## Two source questions, answered before the first byte

### 1. Does the driver ever emit a bare `0x03` outside image payload?  **NO.**

Proven by exhaustion, not by a grep miss. There are exactly **three** call sites
that put bytes on the wire:

| site | what |
|---|---|
| `hostio4.c:264` | `hostio4_write_all(out, out_len)` inside `hostio4_exchange` — every command |
| `hostio4.c:1030` | the single mode-entry `ESC` |
| `hostio4.c:1094` | `"X\r"` on quit |

Every buffer reaching `:264` is built by `sprintf` from an ASCII template:

- `hostio4.c:428`  `"Ax%08" PRIX32 "\r"`
- `hostio4.c:453`  `"R\r"`
- `hostio4.c:456`  `"R%08X\r"`   ← **the block-read count is ASCII hex**, so an
  8-word read emits `'0','0','0','0','0','0','0','8'`, never a raw `0x08`, and a
  3-word read emits `'3'` (`0x33`), never `0x03`
- `hostio4.c:525`  `"Wx%08" PRIX32 "\r"`
- `hostio4.c:573`  `"Ux%08X\r"`
- `hostio4.c:1094` `"X\r"`

The lowest byte any of these can produce is CR `0x0d`. The **only** raw-binary
path in the driver is the payload loop at `hostio4.c:578-581`, inside
`hostio4_do_block_write`, which is gated on `hostio4_block_write` —
default `false` at `hostio4.c:77`, gated at `hostio4.c:626`.

**So with block write off, the driver cannot emit `0x03` at all**, and the
session cannot die mid-command. Confirmed empirically below: `adp-bridge --stats`
reported **0 Ctrl-C dropped** across the whole run.

### 2. Does the reset or resync path emit `ESC` in a way the bridge changes?

**Exactly one `ESC` is ever emitted, at `hostio4.c:1030`, and the bridge DOES
change it — but the dongle changes it back, and it works.**

- The single `ESC` (`ADP_ESC 0x1b`, `hostio4.c:69`) is written by
  `hostio4_write_all(&esc, 1)` at `hostio4.c:1030`, bypassing `hostio4_exchange`.
  It lives in `hostio4_enter_adp()`, which has **one caller**: `hostio4_init()`
  at `hostio4.c:1077`.
- **There is no resync path.** `hostio4_link_dead` is set at `:265`, `:283`,
  `:294` and is cleared only inside `hostio4_enter_adp` (`:1037`) and
  `hostio4_init` (`:1065`). Once the link is declared dead the driver does **not**
  re-enter ADP mode; it stays dead until OpenOCD restarts. So no second `ESC`.
- **`hostio4_reset()` emits ZERO bytes** — it returns `ERROR_OK` with no write
  ("The ADP monitor has no reset line of its own"). The OpenOCD reset path
  therefore emits no `ESC`.
- `hostio4_quit()` emits `"X\r"` only.

The round trip, verified in source on both sides:

```
driver  hostio4.c:1030     emits 0x1b
bridge  adp-bridge:185-188 to_board(): 0x1b -> ']' (0x5d), counts translated_esc
dongle  recovered/main.py:186-188  if txbyte == ']': extio.xiot_tx0(0x1b)
monitor adpmon.py:391-393 / RTL:532-533  ESC is the ONLY entry to command mode
```

So the substitution is undone at the dongle and the monitor receives a real
`ESC`. `haps-hostio console` states the same contract in its own output:
*"']' you type reaches the SoC as ESC (ADP entry) -- a real ESC is eaten here."*

**This was the predicted likeliest failure and it did NOT fail** — mode entry
succeeded on all six OpenOCD invocations (`6 ESC translated`, six
`ADP monitor is responding` lines).

> **Side finding, not exercised.** The dongle remap at `main.py:186` is
> unconditional on stdin: **every** `]` becomes `ESC` at the monitor, not just
> the mode-entry one. The driver's commands are hex+`AxRWUX\r` and contain no
> `0x5d`, so it is harmless here — but it is a **third** block-write payload
> hazard (`0x5d` -> `ESC`) alongside the `0x03` and `0x1b` ones already
> documented in `README.md`. Another reason block write stays off.

---

## Preconditions

| # | precondition | result |
|---|---|---|
| 1 | `haps-board-lock status` | **COULD NOT RUN — the tool does not exist.** See below. |
| 2 | `verify-target` 7/7 before OpenOCD | **7/7 PASS** (log 06) |
| 3 | `unpark` if parked | **not needed** — `adp-enter` passed with `first reply C`, no `UNPARK` reported |

### `haps-board-lock` is not installed anywhere on this system

`module load haps-dev` aliases it to `$tools_root/haps-board-lock`
(`modulefiles/haps-dev/1.0:333`), but that file is absent:

```
$ ls /research/CAD/SoC-Labs-HAPS-SX-Tools/bin/
cfg  haps-hostio  haps-hwserver  haps-openocd  haps-program  haps-serial  haps-state-relay
$ ls /research/CAD/SoC-Labs-HAPS-SX-Tools/bin/haps-board-lock
ls: cannot access '...': No such file or directory
$ type haps-board-lock          # after module load haps-dev
bash: type: haps-board-lock: not found
```

The module's alias is a dangling reference — a deploy gap
(`modulefiles/README.md` §Deploy notes the deploy is manual and both destination
trees are CAD-owned). **The reservation could not be claimed or released through
the documented mechanism.** This run proceeded on the owner's explicit
confirmation that the board was free. No lease was taken and none was left held.

### Ordering correction found the hard way

`verify-target` must run **before** `haps-hostio up`, not after. `up` starts a
`ser2net` that holds the CDC, and `probe`/`verify-target` then refuse with
`dongle_state=held` (log 03, 04 — `held=ser2net:1879741`, which was this run's
own `up`). The first `verify-target` attempt failed for exactly this reason and
is preserved below as log 03/04; after `down pico` it read 7/7 immediately.

`haps-hostio console` must run **last** — it says so itself: every other verb
sends Ctrl-C first and ends the bridge.

**Working order:** `verify-target` -> `up` -> `console` -> `adp-bridge` -> `openocd`.

---

## The chain actually used

```
haps-hostio up pico
haps-hostio console pico
adp-bridge --up hostio:pico \
           --tool /home/dam1n19/SoCLabs/HAPS-work/fpga/haps-sx/hostio/haps-hostio \
           --tcp 127.0.0.1:24900 --stats
openocd -f hostio4-bench.cfg -c init ...
```

`--raw` was NOT passed. The bridge confirmed the translation was live:

```
adp-bridge: upstream pty:/home/dam1n19/.haps-sx/tty-hostio-pico; ESC sent as ']', Ctrl-C DROPPED
adp-bridge: listening on 127.0.0.1:24900
```

`--tool` was required: `adp-bridge` shells out to `haps-hostio` by bare name and
neither it nor `haps-hostio` is on `PATH` after `module load haps-dev`
(first attempt died with `cannot run haps-hostio: [Errno 2] ... 'haps-hostio'`).

---

## Discriminator verdicts

| # | action | discriminator | verdict |
|---|---|---|---|
| 1 | `dap init` | monitor responds, then examination succeeds | **MET** — `ADP monitor is responding`; `targets` shows `chip.ahb mem_ap ... running` |
| 2 | `mdw 0x08000000` | matches the independently-proven path | **MET** — `18003c00`, identical to `verify-target` leg `adp-identity` |
| 3 | `mdw 0x08000000 8` | ONE `R00000008`, not eight singles | **MET** — counters: block reads 0->1, single reads unchanged at 1 |
| 4 | `mww` then `mdw` `0x2100000C` | reads back what was written | **MET** — wrote `0badc0de`, read `0badc0de`, restored `003f01f0` |
| 5 | `mdw` unmapped `0x30000000` | a FAULT, not zeros | **MET** — `AHB bus error ... monitor flagged '!'`, bus faults 0->1 |
| 6 | `mdw 0x2E000000` | driver refuses, ZERO bytes on the wire | **MET** — refused; all five counters byte-identical across the attempt |

Step 3's evidence is the driver's own `hostio4_info` counters rather than a wire
capture: `hostio4_stat_block_reads` (`hostio4.c:457`) increments only on the
`R%08X` path (`:456`) and `hostio4_stat_single_reads` (`:454`) only on the `R\r`
path (`:453`), so `block reads 1 / single reads 1` after one single `mdw` and one
8-word `mdw` is a direct statement about which command form went out.

Step 6's evidence is that all five counters are unchanged across the refused
access. `hostio4_check_span` (`hostio4.c:401-414`) is called at `:663` in the
queueing layer, before any `sprintf` or `write`, so a refusal cannot have emitted
bytes. The bridge's own totals corroborate: the run's 306 bytes out are fully
accounted for by the accesses that were allowed.

---

## `adp-bridge --stats`

```
adp-bridge: 306 bytes to the board, 753 back; 6 ESC translated, 0 Ctrl-C dropped
```

- **6 ESC translated** = exactly one per OpenOCD invocation, across six
  invocations. Confirms question 2: one mode-entry `ESC` per `init`, no resync
  path emitting a second, and all six crossed the translation layer intact.
- **0 Ctrl-C dropped** = the empirical confirmation of question 1. The driver
  emitted no `0x03` in any command, count, address or payload during the entire
  run. Nothing was deleted in transit, so no byte count changed.
- 306 out / 753 back over six sessions is consistent with ASCII commands and
  `LF CR`-framed replies; no transfer reported a drop.

---

## Board state left behind

`verify-target` immediately after the OpenOCD work, with the transport released:

```
  PASS  wires          something_holds_the_wires:_LOW,LOW,HIGH,HIGH,UNSTABLE,UNSTABLE,UNSTABLE_control=FLOAT
  PASS  adp-enter      ESC_accepted,_prompt_']'_seen_(first_reply_C)
  PASS  adp-nobus      Mx0000FF00_read_back_0x0000ff00_(monitor_alive;_this_leg_uses_NO_bus_cycle)
  PASS  adp-error      0x30000000->R!_(flag_RAISES)_and_0x08000000->R_(flag_CLEARS)
  PASS  adp-identity   bootROM_MSP_0x18003c00_CoreSight_CID_0xb105f00d_(4_DIFFERING_words:_not_a_constant_bus)
  PASS  adp-scratch    0x2100000C_wrote_0x0badc0de_read_it_back_restored_0x003f01f0
  PASS  banner         none_pending_-_EXPECTED:_emitted_once_at_reset._Use_--banner-only_to_catch_one
haps-hostio: verify-target pico: 7 pass, 0 fail, 0 skip (of 7 legs)
```

Byte-for-byte the same seven legs as the pre-run check. The scratch register is
back at `003f01f0`. **The monitor was not parked, the board did not wedge, and
nothing needed a reset.**

Transport torn down: `haps-hostio down pico` (ser2net stopped, dongle released),
`adp-bridge` stopped, TCP 24900 closed, PTY `/home/dam1n19/.haps-sx/tty-hostio-pico`
gone. The `ser2net` still running on `haps-dev` (pid 1341061, port 29000) is a
**different device** — a CP2104 UART, not the RP2350 — and was not touched.

### One non-fault worth recording

Between the OpenOCD work and the final check, `haps-hostio read 0x08000000 8`
returned `no ADP prompt (ENTER=absent)` (logs 16, 17) and `verify-target`
returned `dongle_state=held` (log 18). **Neither was a board fault**: `ser2net`
from this run's own `up` still held the CDC. After `down pico` the very next
`verify-target` read 7/7 (log 20). Recorded because `ENTER=absent` reads as a
dead link and is not one — the same class of misreading the driver's
`"is the far end up and in command mode?"` message invites.

---

## Raw logs


### 01-up.txt

```
haps-hostio: pico = HOSTIO4 host (Waveshare RP2350, MicroPython) on PMOD1 (default from /research/CAD/SoC-Labs-HAPS-SX-Tools/etc/haps-hostio.conf)
haps-hostio: device  /dev/serial/by-id/usb-MicroPython_Board_in_FS_mode_e1b0aef0052ab176-if00
haps-hostio: remote  127.0.0.1:28900  (per-dongle: one CDC, one port, one ser2net)
haps-hostio: local   127.0.0.1:28355    (per-user, uid 74755)
haps-hostio: no ssh master and no socat here - an own bridge found on haps-dev would be an ORPHAN and gets reaped
haps-hostio[haps-dev]: ser2net pid 1879741 listening on 127.0.0.1:28900 -> /dev/ttyACM1
haps-hostio: up: /home/dam1n19/.haps-sx/tty-hostio-pico  ->  HOSTIO4 host (Waveshare RP2350, MicroPython)
haps-hostio: attach with:  screen /home/dam1n19/.haps-sx/tty-hostio-pico
haps-hostio:   channel 0 is the SoC CONSOLE only once './haps-hostio console pico' has pushed the
haps-hostio:   bridge; with nothing running on the dongle, that PTY is a MicroPython prompt.
haps-hostio: or drive it:  ./haps-hostio exec pico <file>  (raw REPL, stdlib only, no pyserial)
haps-hostio: release with: ./haps-hostio down pico
```

### 02-console.txt

```
haps-hostio: console: pushing the channel-0 bridge over /home/dam1n19/.haps-sx/tty-hostio-pico
haps-hostio:   this enters the raw REPL, which INTERRUPTS whatever the board is running
haps-hostio: console: the bridge is running, and NO Ctrl-B was sent, so it stays running.
haps-hostio:   attach with:  screen /home/dam1n19/.haps-sx/tty-hostio-pico
haps-hostio:   ']' you type reaches the SoC as ESC (ADP entry) -- a real ESC is eaten here.
haps-hostio:   it ENDS at the next raw-REPL entry by any verb (probe/exec/verify-target/
haps-hostio:   adp/read/write/dump all send Ctrl-C first), and at './haps-hostio down pico'.
haps-hostio:   So run 'console' last.
```

### 03-verify-target.txt

```
haps-hostio: verify-target pico on PMOD1 (default from /research/CAD/SoC-Labs-HAPS-SX-Tools/etc/haps-hostio.conf)
haps-hostio:   This enters the MicroPython raw REPL, which INTERRUPTS main.py on the
haps-hostio:   dongle, and -- if a target answers -- puts the SoC's ADP monitor into
haps-hostio:   command mode and writes one scratch register, restoring it afterwards.
  FAIL  wires          dongle_state=held_-_see_'./haps-hostio_probe'
  skip  adp-enter      not_reached
  skip  adp-nobus      not_reached
  skip  adp-error      not_reached
  skip  adp-identity   not_reached
  skip  adp-scratch    not_reached
  skip  banner         not_reached
haps-hostio: verify-target pico: 0 pass, 1 fail, 6 skip (of 7 legs)
haps-hostio: VERIFY-TARGET FAILED
```

### 04-probe.txt

```
haps-hostio: probe enters the MicroPython raw REPL, which INTERRUPTS any main.py on the board, then soft-reboots it so main.py restarts (--passive writes nothing)
dongle  : pico = HOSTIO4 host (Waveshare RP2350, MicroPython)
          on PMOD1   usb 2e8a:0005 Board in FS mode
          by-id /dev/serial/by-id/usb-MicroPython_Board_in_FS_mode_e1b0aef0052ab176-if00
          node=/dev/ttyACM1 usbfs=/dev/bus/usb/001/022 held=ser2net:1879741
verdict : DONGLE HELD by ser2net:1879741 - refusing to touch it
```

### 05-down.txt

```
haps-hostio: local socat stopped (pid 2347290)
haps-hostio[haps-dev]: ser2net pid 1879741 stopped, dongle released
haps-hostio: down: pico
```

### 06-verify-target-2.txt

```
haps-hostio: verify-target pico on PMOD1 (default from /research/CAD/SoC-Labs-HAPS-SX-Tools/etc/haps-hostio.conf)
haps-hostio:   This enters the MicroPython raw REPL, which INTERRUPTS main.py on the
haps-hostio:   dongle, and -- if a target answers -- puts the SoC's ADP monitor into
haps-hostio:   command mode and writes one scratch register, restoring it afterwards.
  PASS  wires          something_holds_the_wires:_LOW,LOW,HIGH,HIGH,UNSTABLE,UNSTABLE,UNSTABLE_control=FLOAT
  PASS  adp-enter      ESC_accepted,_prompt_']'_seen_(first_reply_C)
  PASS  adp-nobus      Mx0000FF00_read_back_0x0000ff00_(monitor_alive;_this_leg_uses_NO_bus_cycle)
  PASS  adp-error      0x30000000->R!_(flag_RAISES)_and_0x08000000->R_(flag_CLEARS)
  PASS  adp-identity   bootROM_MSP_0x18003c00_CoreSight_CID_0xb105f00d_(4_DIFFERING_words:_not_a_constant_bus)
  PASS  adp-scratch    0x2100000C_wrote_0x0badc0de_read_it_back_restored_0x003f01f0
  PASS  banner         none_pending_-_EXPECTED:_emitted_once_at_reset._Use_--banner-only_to_catch_one
haps-hostio: verify-target pico: 7 pass, 0 fail, 0 skip (of 7 legs)
haps-hostio: VERIFY-TARGET PASSED
```

### 07-up2.txt

```
haps-hostio: pico = HOSTIO4 host (Waveshare RP2350, MicroPython) on PMOD1 (default from /research/CAD/SoC-Labs-HAPS-SX-Tools/etc/haps-hostio.conf)
haps-hostio: device  /dev/serial/by-id/usb-MicroPython_Board_in_FS_mode_e1b0aef0052ab176-if00
haps-hostio: remote  127.0.0.1:28900  (per-dongle: one CDC, one port, one ser2net)
haps-hostio: local   127.0.0.1:28355    (per-user, uid 74755)
haps-hostio: no ssh master and no socat here - an own bridge found on haps-dev would be an ORPHAN and gets reaped
haps-hostio[haps-dev]: ser2net pid 1880353 listening on 127.0.0.1:28900 -> /dev/ttyACM1
haps-hostio: up: /home/dam1n19/.haps-sx/tty-hostio-pico  ->  HOSTIO4 host (Waveshare RP2350, MicroPython)
haps-hostio: attach with:  screen /home/dam1n19/.haps-sx/tty-hostio-pico
haps-hostio:   channel 0 is the SoC CONSOLE only once './haps-hostio console pico' has pushed the
haps-hostio:   bridge; with nothing running on the dongle, that PTY is a MicroPython prompt.
haps-hostio: or drive it:  ./haps-hostio exec pico <file>  (raw REPL, stdlib only, no pyserial)
haps-hostio: release with: ./haps-hostio down pico
```

### 08-console2.txt

```
haps-hostio: console: pushing the channel-0 bridge over /home/dam1n19/.haps-sx/tty-hostio-pico
haps-hostio:   this enters the raw REPL, which INTERRUPTS whatever the board is running
haps-hostio: console: the bridge is running, and NO Ctrl-B was sent, so it stays running.
haps-hostio:   attach with:  screen /home/dam1n19/.haps-sx/tty-hostio-pico
haps-hostio:   ']' you type reaches the SoC as ESC (ADP entry) -- a real ESC is eaten here.
haps-hostio:   it ENDS at the next raw-REPL entry by any verb (probe/exec/verify-target/
haps-hostio:   adp/read/write/dump all send Ctrl-C first), and at './haps-hostio down pico'.
haps-hostio:   So run 'console' last.
```

### 09-bridge.log

```
adp-bridge: upstream pty:/home/dam1n19/.haps-sx/tty-hostio-pico; ESC sent as ']', Ctrl-C DROPPED
127.0.0.1:24900
adp-bridge: listening on 127.0.0.1:24900
adp-bridge: 306 bytes to the board, 753 back; 6 ESC translated, 0 Ctrl-C dropped
```

### 10-step1-init.txt

```
Open On-Chip Debugger 0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)
Licensed under GNU GPL v2
For bug reports, read
	http://openocd.org/doc/doxygen/bugs.html
Info : only one transport option; autoselect 'dapdirect_swd'
Warn : Transport "dapdirect_swd" was already selected
hostio4_d2d_guard
Warn : An adapter speed is not selected in the init scripts. OpenOCD will try to run the adapter at the low speed (100 kHz)
Warn : To remove this warnings and achieve reasonable communication speed with the target, set "adapter speed" or "jtag_rclk" in the init scripts.
Info : hostio4: connecting to tcp 127.0.0.1:24900
Info : hostio4: ADP monitor is responding on 127.0.0.1:24900
Info : clock speed 100 kHz
Info : gdb port disabled
```

### 11-step1b-examine.txt

```
Open On-Chip Debugger 0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)
Licensed under GNU GPL v2
For bug reports, read
	http://openocd.org/doc/doxygen/bugs.html
Info : only one transport option; autoselect 'dapdirect_swd'
Warn : Transport "dapdirect_swd" was already selected
hostio4_d2d_guard
Warn : An adapter speed is not selected in the init scripts. OpenOCD will try to run the adapter at the low speed (100 kHz)
Warn : To remove this warnings and achieve reasonable communication speed with the target, set "adapter speed" or "jtag_rclk" in the init scripts.
Info : hostio4: connecting to tcp 127.0.0.1:24900
Info : hostio4: ADP monitor is responding on 127.0.0.1:24900
Info : clock speed 100 kHz
Info : gdb port disabled
    TargetName         Type       Endian TapName            State       
--  ------------------ ---------- ------ ------------------ ------------
 0* chip.ahb           mem_ap     little chip.cpu           running

examined=running
```

### 12-step2-3.txt

```
Open On-Chip Debugger 0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)
Licensed under GNU GPL v2
For bug reports, read
	http://openocd.org/doc/doxygen/bugs.html
Info : only one transport option; autoselect 'dapdirect_swd'
Warn : Transport "dapdirect_swd" was already selected
hostio4_d2d_guard
Warn : An adapter speed is not selected in the init scripts. OpenOCD will try to run the adapter at the low speed (100 kHz)
Warn : To remove this warnings and achieve reasonable communication speed with the target, set "adapter speed" or "jtag_rclk" in the init scripts.
Info : hostio4: connecting to tcp 127.0.0.1:24900
Info : hostio4: ADP monitor is responding on 127.0.0.1:24900
Info : clock speed 100 kHz
Info : gdb port disabled
--- baseline counters ---
hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 0, word writes 0, block writes 0, bus faults 0

--- STEP 2: mdw 0x08000000 (expect 0x18003c00) ---
0x08000000: 18003c00 

hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 1, word writes 0, block writes 0, bus faults 0

--- STEP 3: mdw 0x08000000 8 ---
0x08000000: 18003c00 08000189 080001cd 080001cf 00000000 00000000 00000000 00000000 

hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 1, single reads 1, word writes 0, block writes 0, bus faults 0

```

### 13-step4.txt

```
Open On-Chip Debugger 0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)
Licensed under GNU GPL v2
For bug reports, read
	http://openocd.org/doc/doxygen/bugs.html
Info : only one transport option; autoselect 'dapdirect_swd'
Warn : Transport "dapdirect_swd" was already selected
hostio4_d2d_guard
Warn : An adapter speed is not selected in the init scripts. OpenOCD will try to run the adapter at the low speed (100 kHz)
Warn : To remove this warnings and achieve reasonable communication speed with the target, set "adapter speed" or "jtag_rclk" in the init scripts.
Info : hostio4: connecting to tcp 127.0.0.1:24900
Info : hostio4: ADP monitor is responding on 127.0.0.1:24900
Info : clock speed 100 kHz
Info : gdb port disabled
--- original value (verify-target says 0x003f01f0) ---
0x2100000c: 003f01f0 

--- write 0x0badc0de (the value verify-target proved safe) ---
--- read back ---
0x2100000c: 0badc0de 

--- RESTORE 0x003f01f0 ---
0x2100000c: 003f01f0 

hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 3, word writes 2, block writes 0, bus faults 0

```

### 14-step5.txt

```
Open On-Chip Debugger 0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)
Licensed under GNU GPL v2
For bug reports, read
	http://openocd.org/doc/doxygen/bugs.html
Info : only one transport option; autoselect 'dapdirect_swd'
Warn : Transport "dapdirect_swd" was already selected
hostio4_d2d_guard
Warn : An adapter speed is not selected in the init scripts. OpenOCD will try to run the adapter at the low speed (100 kHz)
Warn : To remove this warnings and achieve reasonable communication speed with the target, set "adapter speed" or "jtag_rclk" in the init scripts.
Info : hostio4: connecting to tcp 127.0.0.1:24900
Info : hostio4: ADP monitor is responding on 127.0.0.1:24900
Info : clock speed 100 kHz
Info : gdb port disabled
--- expect an ERROR, not a value ---
Error: hostio4: AHB bus error reading 0x30000000 (the monitor flagged '!'); OpenOCD may report the following word instead
Error: Failed to read memory at 0x30000004
result-> 
hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 1, word writes 0, block writes 0, bus faults 1

--- and the bus still works afterwards (flag must CLEAR) ---
0x08000000: 18003c00 

hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 2, word writes 0, block writes 0, bus faults 1

```

### 15-step6.txt

```
Open On-Chip Debugger 0.12.0-g9ea7f3d-dirty (2026-09-18-10:31)
Licensed under GNU GPL v2
For bug reports, read
	http://openocd.org/doc/doxygen/bugs.html
Info : only one transport option; autoselect 'dapdirect_swd'
Warn : Transport "dapdirect_swd" was already selected
hostio4_d2d_guard
Warn : An adapter speed is not selected in the init scripts. OpenOCD will try to run the adapter at the low speed (100 kHz)
Warn : To remove this warnings and achieve reasonable communication speed with the target, set "adapter speed" or "jtag_rclk" in the init scripts.
Info : hostio4: connecting to tcp 127.0.0.1:24900
Info : hostio4: ADP monitor is responding on 127.0.0.1:24900
Info : clock speed 100 kHz
Info : gdb port disabled
--- counters BEFORE the D2D attempt ---
hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 0, word writes 0, block writes 0, bus faults 0

--- attempt 0x2E000000: expect DRIVER refusal, no traffic ---
Error: hostio4: refusing access to 0x2e000000..0x2e000003: it overlaps the die-to-die window 0x2e000000-0x2fffffff. The ADP monitor has no bus timeout, so an access there with the D2D link down stalls the AHB until the chip is reset.
Error: Failed to read memory and, additionally, failed to find out where
result-> 
--- counters AFTER: must be IDENTICAL ---
hostio4 (nanoSoC ADP monitor) adapter:
 port          : 127.0.0.1:24900
 base offset   : 0x00000000
 block size    : 16 words
 cmd timeout   : 4000 ms
 block write   : off (W per word)
 D2D blacklist : 0x2e000000-0x2fffffff
 wire stats    : block reads 0, single reads 0, word writes 0, block writes 0, bus faults 0

--- board still alive? ---
0x08000000: 18003c00 

```

### 16-crosscheck-read.txt

```
haps-hostio: read: no ADP prompt (ENTER=absent) -- './haps-hostio verify-target' has the full picture
```

### 17-crosscheck-scratch.txt

```
haps-hostio: read: no ADP prompt (ENTER=absent) -- './haps-hostio verify-target' has the full picture
```

### 18-verify-target-post.txt

```
haps-hostio: verify-target pico on PMOD1 (default from /research/CAD/SoC-Labs-HAPS-SX-Tools/etc/haps-hostio.conf)
haps-hostio:   This enters the MicroPython raw REPL, which INTERRUPTS main.py on the
haps-hostio:   dongle, and -- if a target answers -- puts the SoC's ADP monitor into
haps-hostio:   command mode and writes one scratch register, restoring it afterwards.
  FAIL  wires          dongle_state=held_-_see_'./haps-hostio_probe'
  skip  adp-enter      not_reached
  skip  adp-nobus      not_reached
  skip  adp-error      not_reached
  skip  adp-identity   not_reached
  skip  adp-scratch    not_reached
  skip  banner         not_reached
haps-hostio: verify-target pico: 0 pass, 1 fail, 6 skip (of 7 legs)
haps-hostio: VERIFY-TARGET FAILED
```

### 19-down2.txt

```
haps-hostio: local socat stopped (pid 2356599)
haps-hostio[haps-dev]: ser2net pid 1880353 stopped, dongle released
haps-hostio: down: pico
```

### 20-verify-target-final.txt

```
haps-hostio: verify-target pico on PMOD1 (default from /research/CAD/SoC-Labs-HAPS-SX-Tools/etc/haps-hostio.conf)
haps-hostio:   This enters the MicroPython raw REPL, which INTERRUPTS main.py on the
haps-hostio:   dongle, and -- if a target answers -- puts the SoC's ADP monitor into
haps-hostio:   command mode and writes one scratch register, restoring it afterwards.
  PASS  wires          something_holds_the_wires:_LOW,LOW,HIGH,HIGH,UNSTABLE,UNSTABLE,UNSTABLE_control=FLOAT
  PASS  adp-enter      ESC_accepted,_prompt_']'_seen_(first_reply_C)
  PASS  adp-nobus      Mx0000FF00_read_back_0x0000ff00_(monitor_alive;_this_leg_uses_NO_bus_cycle)
  PASS  adp-error      0x30000000->R!_(flag_RAISES)_and_0x08000000->R_(flag_CLEARS)
  PASS  adp-identity   bootROM_MSP_0x18003c00_CoreSight_CID_0xb105f00d_(4_DIFFERING_words:_not_a_constant_bus)
  PASS  adp-scratch    0x2100000C_wrote_0x0badc0de_read_it_back_restored_0x003f01f0
  PASS  banner         none_pending_-_EXPECTED:_emitted_once_at_reset._Use_--banner-only_to_catch_one
haps-hostio: verify-target pico: 7 pass, 0 fail, 0 skip (of 7 legs)
haps-hostio: VERIFY-TARGET PASSED
```

---

*Run by Agent C, 2026-09-22. Not committed, per the run brief. No lease was
taken (`haps-board-lock` does not exist); the board was free by the owner's
confirmation and was released by `haps-hostio down pico`.*
