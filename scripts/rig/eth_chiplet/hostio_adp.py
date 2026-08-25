#!/usr/bin/env python3
"""hostio_adp.py - ADP debug client over the HOSTIO4 link (RP2350 host).

FIRST WORKING HOSTIO4 LINK, 2026-08-25. Proven bidirectional against the
eth_ss_0 backdoor on three independent values:
    0x2E0321F8 -> 0xb5000001   (TL-009 witness, marker 0xB5)
    0x2E0321E0 -> 0xad800000   (marker 0xAD)
    0x08000000 -> 0x18003c00   (boot ROM, same word eth_ss_probe.py checks)
Write path proven by write/read-back/restore at IMEM 0x00001000.

USAGE (from a host that can see the RP2350's MicroPython CDC port):
    python3 hostio_adp.py /dev/ttyACM4 read  0x2E0321F8
    python3 hostio_adp.py /dev/ttyACM4 write 0x00001000 0xD00DFEED
    python3 hostio_adp.py /dev/ttyACM4 shell "Ax08000000" "R"

THREE TRAPS, ALL MEASURED:

 1. sm0.put() BLOCKS when its TX FIFO is full. That is the documented hang and
    it is how this port was wedged repeatedly. Every put() here is guarded on
    tx_fifo() < 4.

 2. The host PIO has NO TIMEOUT and cannot resynchronise. If SM0 samples RQ1
    high while the FPGA is unconfigured (jmp pin -> "command" at instr 5) it
    parks at instr 8/22 holding ACK HIGH -- and ioack high pins the SoC FSM in
    OFFZ forever (start_xfer = cmd_req & !ioack_s). Symptom: ioreq1/ioreq2 dead
    at 0, sm0.tx_fifo() stuck at 4, nothing ever received. resync() below fixes
    it; pump() calls it automatically when SM0 sits outside the idle loop.
    NOTE resync() reloads X=0, so the status nibble must be re-advertised
    immediately afterwards or the SoC sees "host has nothing to do".

 3. The FIRST command after ESC is always rejected with '?'. Send a throwaway
    command (this client uses 'C') before anything that matters.

RX words are 12 bits: only words with (w & 0xf00) == 0 are console data bytes;
the rest are flow/control and WILL corrupt a naive ASCII decode.

An undecoded address does NOT hang the monitor: it answers 'R!0x00000000' --
'!' in place of the space is the bus-error flag. The console stays fully usable.
"""
import serial, time, sys

BOARD = (
 "import machine,extio,time\r\n"
 "P0=0x50200000; PCR=P0+0x0d4; SH=P0+0x0d0\r\n"
 "def resync():\r\n"
 "    extio.sm0.active(0)\r\n"
 "    v=machine.mem32[SH]; machine.mem32[SH]=v^0x40000000; machine.mem32[SH]=v\r\n"
 "    extio.sm0.restart(); extio.sm0.active(1)\r\n"
 "RX=[]\r\n"
 "LAST_OK=[0]\r\n"
 "def pump(ms, stuck_ms=120):\r\n"
 "    t0=time.ticks_ms()\r\n"
 "    while time.ticks_diff(time.ticks_ms(),t0)<ms:\r\n"
 "        if extio.sm0.tx_fifo()<4: extio.sm0.put(extio.get_xiot_fifo_status())\r\n"
 "        while extio.sm0.rx_fifo(): RX.append(extio.sm0.get())\r\n"
 "        if machine.mem32[PCR]>11:\r\n"
 "            if time.ticks_diff(time.ticks_ms(),LAST_OK[0])>stuck_ms:\r\n"
 "                resync()\r\n"
 "                extio.sm0.put(extio.get_xiot_fifo_status())\r\n"
 "                LAST_OK[0]=time.ticks_ms()\r\n"
 "        else: LAST_OK[0]=time.ticks_ms()\r\n"
 "def send(t):\r\n"
 "    for ch in t:\r\n"
 "        t0=time.ticks_ms()\r\n"
 "        while extio.sm1.tx_fifo()>=4 and time.ticks_diff(time.ticks_ms(),t0)<400: pump(5)\r\n"
 "        if extio.sm1.tx_fifo()<4: extio.xiot_tx0(ord(ch))\r\n"
 "        pump(25)\r\n"
 "def txt():\r\n"
 "    global RX\r\n"
 "    t=''.join(chr(w&0xff) for w in RX if (w & 0xf00)==0 and 32<=(w&0xff)<127)\r\n"
 "    RX=[]; return t.strip()\r\n"
 "def cmd(c,ms=2200):\r\n"
 "    send(c+chr(0x0d)); pump(ms); return txt()\r\n"
 "def enter():\r\n"
 "    LAST_OK[0]=time.ticks_ms()\r\n"
 "    resync(); pump(500); send(chr(0x1b)); pump(1000); txt(); cmd('C')\r\n")


def repl(port, body, wait):
    s = serial.Serial(port, 115200, timeout=3)
    s.write(b'\x03'); time.sleep(0.25); s.reset_input_buffer()
    s.write(b'\x01'); time.sleep(0.25); s.reset_input_buffer()
    s.write((BOARD + body).encode() + b'\x04'); time.sleep(wait)
    out = s.read(1500000).decode(errors="replace")
    s.write(b'\x02'); s.close()
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    port, op = sys.argv[1], sys.argv[2]
    if op == "read":
        a = int(sys.argv[3], 0)
        print(repl(port, "enter()\r\ncmd('Ax%08X')\r\nprint(cmd('R'))\r\n" % a, 30.0))
    elif op == "write":
        a, v = int(sys.argv[3], 0), int(sys.argv[4], 0)
        print(repl(port, "enter()\r\ncmd('Ax%08X')\r\nprint(cmd('Wx%08X'))\r\n"
                         "cmd('Ax%08X')\r\nprint('readback',cmd('R'))\r\n" % (a, v, a), 40.0))
    elif op == "shell":
        body = "enter()\r\n" + "".join("print(%r,cmd(%r))\r\n" % (c, c) for c in sys.argv[3:])
        print(repl(port, body, 20.0 + 6.0 * len(sys.argv[3:])))
    else:
        print(__doc__); sys.exit(1)


if __name__ == "__main__":
    main()
