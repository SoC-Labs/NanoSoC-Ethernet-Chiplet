# HAPS-SX Bench — Access, Tooling and Known Issues

> Working notes for the SoC-Labs HAPS-SX bench. Measurements dated 2026-08-26.
> Internal — contains hostnames and addresses specific to the Southampton CAD environment.

## 1. Topology

```
 workstation (srv03335, srv04936 ...)
        │  ssh
        ▼
 haps-dev.ecs.soton.ac.uk          jump host, RHEL 8.10
   ├── ecs-lan      Intel e1000e   campus
   ├── bench-lan    Realtek r8169  10.60.2.1 / 10.60.3.1  (100 Mb by design)
   └── haps-boards  Realtek r8169  10.60.1.1              (see §6 — known fault)
                          │
                     [switch, unmanaged or unreachable]
                          ├── 10.60.1.10  haps-sx    HAPS-SX VU19P 1F 28G
                          └── 10.60.1.11  hapszynq   Zynq companion
```

Workstations have **no route** to `10.60.0.0/16`. Everything reaches the boards through `haps-dev`.

| Host | Address | Notes |
|---|---|---|
| `haps-dev` | campus DNS | jump host; ssh as root |
| `haps-sx` | 10.60.1.10 | board; ssh user `soclabs`, ProxyJump haps-dev |
| `hapszynq` | 10.60.1.11 | ssh user `petalinux`, ProxyJump haps-dev |
| `haps-sw01` | 10.60.3.2 | managed switch on **bench-lan**, not the board segment |

`/apps` is **not** mounted on haps-dev. It has its own ConfPro install at `/opt/confpro_sx/`.
Its `/home` is local disk, not your NFS home.

## 2. Modules

| Module | Loads | Use |
|---|---|---|
| `haps-dev/1.0` | vivado + confpro_sx + haps-tunnel | Everyday flow; ILA debug via hw_server |
| `haps-identify/1.0` | + synplify + identify + verdi | Synopsys IICE / FSDB debug route |
| `haps-tunnel/1.0` | *(standalone)* | Bench tunnel + UDP board-state relay |
| `haps-sx-tools/1.0` | *(legacy)* | Old ProtoCompiler flow |

`haps-dev`, `haps-identify` and `haps-sx-tools` are mutually exclusive.

## 3. ConfPro-SX uses two channels

This is the single most misunderstood thing about the bench.

| Channel | Carries | Tunnellable |
|---|---|---|
| **TCP 18000** | session/command — System, Power, Clock, Program, Reset | ✅ `ssh -L` |
| **UDP 18009 → 18008** | **all 25 board-state fields**, incl. `control`/`controller` | ❌ `ssh -L` is TCP-only |

The state channel is `SearchCABNet::touchBorad()` — what the GUI calls to refresh a
*manually added* board, i.e. exactly the seeded entry a tunnelled user has.

`confpro-sx-shadow` seeds `boardinfolist.json` with **6 identity fields**; the other
**19 are state** and arrive only over UDP.

**Why this matters beyond cosmetics.** `SystemSelectionDialog::addItem` paints a row grey and
labels it *Used* only when the UDP-sourced `control` flag is true — otherwise **white, "Idle"**.
`on_selectButton_clicked` gates the *Board is Busy* popup on the same flag. With no UDP reply
the flag is always false, so **a board someone else is holding looks free and the GUI connects
to it anyway.**

> The claim that "TCP 18000 is all the GUI needs" appears in several places in-tree. It is
> **true of the CLI and false of the GUI** — `Confpro-SX-Cmd` has 0 `QUdpSocket` imports, the
> GUI has 6. So `confpro-program` / `fpga_config.sh` really do need only 18000.

`bin/haps-state-relay` carries the UDP channel over the tunnel's existing ssh ControlMaster.
Three details are load-bearing:

- it **never binds 18008** — the GUI holds that port exclusively *and ignores the bind failure*,
  so anything else holding it blinds the GUI silently (this includes `haps-board-probe`);
- it replies **from** `127.0.0.1:18009`, reusing the receiving socket;
- it rewrites **`active ip`** to the local endpoint, because `onSysRefreshBoard` copies the
  payload's address over the stored one and `connectBoard` dials it — relaying the board's real
  `10.60.1.10` would redirect the GUI off the working tunnel.

### Who has the board — naming the holder

The board reports `controller` as the **peer IP of whoever holds the TCP session**. Through the
tunnel that is always `10.60.1.1` (the jump host), because `ssh -L` originates the board-side
connection there — so ConfPro's *Board is Busy* popup can never identify a person by itself.

`haps-state-relay` substitutes the holder's name from `haps-board-lock` into that field before
the GUI sees it, so the popup reads:

```
Board is Busy
User : dam1n19@srv03335 (45m left) - bring-up
```

Rules it follows:

- only relabels when the **board itself** says `control` is true — the busy/idle verdict stays
  the board's, never ours
- only when a **live** booking exists; an expired or absent reservation leaves the board's own
  value untouched, so a stale lease can never invent a holder
- `HAPS_STATE_NAME_HOLDER=0` disables it

Safe because `controller` is display-only: `GuiTools::isIpAddr` is called from exactly two
places in the GUI, both *Add Board* input validators, neither on this path. `haps-state-relay
probe` still reports the board's raw value, so the shell tools stay truthful.

All tunnelled users key their lease on the same local endpoint, so they share one lease file —
which is what makes this work across users.

## 4. Getting a board programmed from a workstation

```bash
module load haps-dev            # brings up the tunnel + state relay
export CONFPRO_BOARD=127.0.0.1
confpro-sx                      # GUI
```

Board state from a shell (works where the GUI cannot reach the board at all):

```bash
haps-state-relay probe          # reachable / idle-or-used / holder
haps-state-relay status
```

CLI programming (TCP-only, no UDP dependency):

```bash
confpro-program -f /path/to/design.bin
```

`fpga_config.sh` hardcodes `-t=200000` (200 s) for the upload. On a healthy link a 199 MB
bitstream crosses in ~2 s. A missing sibling `.cfg` file is **not** fatal.

**Do not** reopen the System Selection dialog once `Fpu Cmd Fast Config` has started — its
rescan runs a nested 3-second event loop and rebinds UDP 18008.

## 5. Per-user tunnels — what is and isn't possible

**Current behaviour: the tunnel is host-global.** `haps-tunnel` binds `127.0.0.1:18000`,
`:3121` and `:18009`. Loopback TCP has **no per-user access control**, so any local user on the
same workstation can use another user's forward — over that user's ssh credential. This has
been observed in practice.

### Options, ranked

| Approach | Enforces? | Root? | Verdict |
|---|---|---|---|
| **Per-user loopback address** (`127.0.0.<f(uid)>`) | No | No | **Recommended.** Each user runs their own tunnel with their own credential and lifetime. Removes *accidental* sharing and fixes attribution, but does not prevent a determined local user from connecting. |
| **ssh `-L` to a Unix socket** + per-user TCP↔unix relay | **Yes** — filesystem perms (0600) | No | Real enforcement, unprivileged. Costs one small relay process because ConfPro needs a TCP endpoint. OpenSSH 8.0 here supports it. |
| **Network namespace per user** | Yes | Effectively yes | **Not viable on srv03335.** Unprivileged netns works, but there is no `slirp4netns`/`pasta`/`podman` installed to give the namespace outbound connectivity, so ssh cannot reach haps-dev from inside. |
| **iptables `-m owner --uid-owner`** | Yes | Yes | Real enforcement but needs root and a rule per user; doesn't scale. |
| Different port per user | No | No | Obscurity only. |

### The constraint that outranks all of this

**The board permits only ONE ConfPro session at a time**, and every tunnelled client reaches it
from `10.60.1.1` (the jump host's bench-lan address). So the board **cannot tell users apart**,
and only one person can use it at a time regardless of how the tunnels are arranged.
`haps-board-lock` decides "is this lock mine?" by matching the board's reported holder against
local `hostname -I`, which can never match on a tunnelled host.

**Therefore:** per-user tunnels are worth doing for credential hygiene and lifetime correctness,
but they do **not** solve contention. Coordination has to happen above the tunnel — that is what
the `haps-board-lock` reservation is for. Fixing the tunnel without using the lease just moves
the collision.

**Recommendation:** adopt per-user loopback addresses (cheap, no root, fixes the accidental
case), and treat `haps-board-lock` as mandatory before touching a board. Move to the Unix-socket
scheme only if you need enforcement against a deliberate local user.

## 6. Known issue — board segment runs at 1 Mbps unless forced to master

**Symptom.** Programming from any host is glacial or times out. ConfPro greys out after ~150 s
(`waitOperation(150000)`).

**Cause.** haps-dev's `haps-boards` NIC (Realtek RTL8168D, `r8169`, PCI `0000:06:00.0`) cannot
loop-time reliably as a 1000BASE-T **slave**. In 1000BASE-T the master transmits on its own
clock; the slave recovers the clock from the master and loop-times its transmit to it. This
PHY's recovery is marginal, so as slave its **transmit** is unreadable at the far end.

| haps-dev role @ 1 Gbps | 1472 B loss (.10 / .11) | haps-dev → board TCP |
|---|---|---|
| **slave** (autoneg default) | 10–16% | **134 KiB/s (1 Mbps)** |
| **forced master** | **0% / 0%** | **113 MB/s (906 Mbps)** |

**Fix, applied 2026-08-26:**

```bash
ethtool -s haps-boards autoneg on speed 1000 duplex full master-slave forced-master
```

Made persistent by `/etc/NetworkManager/dispatcher.d/50-haps-boards-gigabit`, which reapplies
it on every NM activation. NetworkManager 1.40 exposes no ethtool master-slave property and
systemd `.link` files have no such key, so a dispatcher hook is the only mechanism that
reapplies on boot and on carrier bounce.

**It is not a cable fault.** 1000BASE-T is dual-duplex — all four pairs carry both directions
simultaneously — so 900+ Mbps in either direction proves the pairs are sound. Device-to-device
traffic across the same switch runs at 906 Mbps. Kernel source corroborates the NIC: the PHY
init for this exact chip revision carries a named `/* Rx Error Issue */` analog workaround
alongside `/* Fine tune PLL performance */`.

**Permanent fix:** replace that NIC with an Intel part (i210/i350). All three ports on haps-dev
are currently in use, and `bench-lan` is not a spare gigabit port — its switch only advertises
100 Mb.

**Health check (30 s):**

```bash
ssh haps-dev 'ping -c 30 -i 1 -W 2 -M do -s 1472 10.60.1.10 | tail -2'
```

0% loss = healthy. Anything above ~1% and programming will be broken.

## 6a. The tunnel: two channels, each failing loudly

`haps-tunnel` opens **two** ssh masters, not one:

| Channel | Forward | ControlPath |
|---|---|---|
| board (ConfPro) | `127.0.0.1:18000 -> haps-sx:18000` | `~/.ssh/cm-haps-tunnel` — the state relay multiplexes on this |
| JTAG (hw_server) | `127.0.0.1:3121 -> localhost:3121` | `~/.ssh/cm-haps-jtag` |

Both run **`ExitOnForwardFailure=yes`**, and the bind address is **pinned and numeric**. Three
things this fixes, all measured:

- An earlier revision omitted `ExitOnForwardFailure`, reasoning that a rebooting board must not
  tear down the JTAG forward. That is wrong — `ssh_config(5)` states it "does not apply to
  connections made over port forwardings"; it fires **only on bind/listen failure**. The cost
  was that when another user (or a stray `hw_server`) held a port, ssh backgrounded
  successfully with a **dead forward**, reported "up", and your tools silently used the other
  user's forward on their credential.
- `ssh -O forward` returns **0 even when the bind fails**, so per-forward failure cannot be
  detected on a single connection. Hence two masters — a stray `hw_server` on 3121 can no
  longer take ConfPro down with it.
- The bind address must be numeric and explicit. Left dual-stack, a v4 collision is masked by a
  successful `[::1]` bind and `ExitOnForwardFailure` never fires. `localhost` also resolves to
  `::1` **first** here, so every consumer URL (`HW_SERVER_URL`) is numeric too.

## 6b. The reservation key

`HAPS_LOCK_KEY` names the **board**, independent of how you reach it. Previously the key came
from `$CONFPRO_BOARD`, so it changed with your transport — `127.0.0.1.lock` tunnelled,
`haps-sx.haps-net.lock` on-segment, `10.60.1.10.lock` on the jump host, and back again after
`module unload haps-tunnel`. Users on different paths **never excluded one another**.

Three consumers must agree on this key: `haps-board-lock`, `confpro-lease.c`, and
`haps-state-relay`'s holder-naming. The relay accepts **either** key during the migration.

## 7. Other traps

- **A local `hw_server` on port 3121 silently defeats the JTAG forward.** `bin/haps-tunnel`
  deliberately omits `ExitOnForwardFailure` (so a rebooting board can't drop the JTAG forward),
  which means ssh's `-L 3121` bind failure is silent and Vivado attaches to the *local*
  hw_server instead of the bench one.
- **Never run `haps-board-probe` while the ConfPro GUI is open** — it binds UDP 18008, which the
  GUI holds exclusively and whose bind failure the GUI ignores. The GUI goes stateless with no
  error.
- **Never touch MMD registers (0x0D/0x0E) on this PHY.** Kernel commit `0231b1a074c6` stubs them
  out because indirect MMD access returns garbage *and writing causes the PHY to malfunction*.
- **firewalld on haps-dev** (zone `boards-haps`) permits only dhcp/dns/ntp/ssh + 3121, 2542 tcp.
  The board's UDP 1534 hw_server beacons are rejected, so Xilinx board discovery is blocked.
- **The r8169 has no internal loopback or TDR.** `ethtool -t` and `--cable-test` are both
  unimplemented for this part; Realtek's cable test needs OCP paging this chip lacks, and
  requires the link down anyway.

## 8. Deploying the modulefiles

The modulefiles are staged in `fpga/haps-sx/modulefiles/` and are **not live** — the live tree
and `/apps` are root/CAD-owned.

1. Copy `haps-tunnel/`, `haps-dev/`, `haps-identify/` into `/research/CAD/EDA-Modulefiles/tools/`
2. `install -m 0755 bin/haps-tunnel bin/haps-state-relay /apps/synopsys/haps/haps-sx/bin/`
   — **both**; `haps-tunnel` locates the relay beside itself, and installing one without the
   other silently returns the grey panel
3. Optionally de-privilege the ssh with a forward-only `jtag` account. **Note:** the relay runs
   a remote *command*, so a `command=""` restriction that permits only port-forwarding will
   disable board state
4. Bind `hw_server` on haps-dev to localhost so 3121 doesn't leave the LAN

Until then, point `HAPS_TUNNEL_BIN` at the repo copy.
