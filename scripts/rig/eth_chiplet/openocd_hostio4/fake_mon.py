#!/usr/bin/env python3
"""fake_mon.py -- a deliberately MISBEHAVING ADP monitor, for fault injection.

NOT a reference monitor. For what the monitor does, use HAPS-work
fpga/haps-sx/hostio/adpmon.py (RTL-cited, byte-exact). This speaks just enough
of the protocol (ESC, Ax, R, R<n>, Wx, X) to get the real openocd + hostio4
through init, then misbehaves in ONE of these ways -- each a failure the far
end of a real bench can produce and adpmon.py, being faithful, never will:

  chatter-init  stream console text from the moment the client connects, one
                line every 2 ms (firmware printf()ing on the shared console):
                the link is never quiet for 50 ms, but answers commands
  chatter-cmd   answer normally until command AFTER, then stream console text
                with no ']' until the client goes away
  flood-cmd     as chatter-cmd, but with no pause at all: the socket always
                holds unread bytes, so a reader that only checks its deadline
                when it runs dry never checks it
  drop-one      answer block reads (R<n>) with the THIRD reply line garbled
                in transit ("R 0x" -> "R 0", a lost byte), everything else
                normal

  fake_mon.py MODE PORT [AFTER]      (AFTER defaults to 3)

Prints "listening" once bound; serves one client and exits when it leaves.
Written by the 2026-09-23 driver review; used by test_driver_fixes.sh.
"""
import socket
import sys
import threading
import time

MODES = ("chatter-init", "chatter-cmd", "flood-cmd", "drop-one")
mode, port = sys.argv[1], int(sys.argv[2])
if mode not in MODES:
    sys.exit("fake_mon: unknown mode %r (one of %s)" % (mode, ", ".join(MODES)))
after = int(sys.argv[3]) if len(sys.argv) > 3 else 3
LINE = b"hello from CPU0 printf loop\r\n"
mem = {}
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(1)
print("listening", flush=True)
c, _ = s.accept()


def stream():
    while True:
        try:
            c.sendall(LINE)
        except OSError:
            return
        time.sleep(0.002)


def flood():
    chunk = LINE * 2048
    while True:
        try:
            c.sendall(chunk)
        except OSError:
            return


if mode == "chatter-init":
    threading.Thread(target=stream, daemon=True).start()

addr = 0
ncmd = 0
buf = b""


def rep(letter, v):
    return b"%c 0x%08x\n\r" % (ord(letter), v & 0xffffffff)


while True:
    try:
        d = c.recv(4096)
    except OSError:
        break
    if not d:
        break
    buf += d.replace(b"\x1b", b"")
    while b"\r" in buf:
        line, buf = buf.split(b"\r", 1)
        line = line.decode("ascii", "replace")
        if not line:
            continue
        ncmd += 1
        print("cmd %d: %r" % (ncmd, line), flush=True)
        if mode in ("chatter-cmd", "flood-cmd") and ncmd >= after:
            print("-> %s forever, no prompt" % ("flooding" if mode == "flood-cmd"
                                               else "streaming"), flush=True)
            (flood if mode == "flood-cmd" else stream)()
            sys.exit(0)
        out = b""
        if line.startswith("Ax"):
            addr = int(line[2:], 16)
            out = rep("A", addr) + b"]"
        elif line == "R":
            out = rep("R", mem.get(addr, addr)) + b"]"
            addr += 4
        elif line.startswith("R"):
            n = int(line[1:], 16)
            for i in range(n):
                v = mem.get(addr, 0x11111111 * (i + 1))
                r = rep("R", v)
                if mode == "drop-one" and i == 2:
                    r = r.replace(b"R 0x", b"R 0", 1)    # one byte lost in transit
                out += r
                addr += 4
            out += b"]"
        elif line.startswith("Wx"):
            mem[addr] = int(line[2:], 16)
            out = rep("W", mem[addr]) + b"]"
            addr += 4
        elif line == "X":
            out = b"\n"
        try:
            c.sendall(out)
        except OSError:
            break
