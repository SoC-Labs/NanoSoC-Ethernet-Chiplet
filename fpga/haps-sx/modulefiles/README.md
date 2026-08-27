# HAPS-SX development modulefiles

A reviewable drop for the CAD/IT change. **Nothing here is live** — the files are staged
in the repo; deploying them is the manual step in §Deploy (the live modulefile tree and
`/apps` are root/CAD-owned and shared across all `arm` users).

## Modules provided
| Module | Loads | Use |
|--------|-------|-----|
| `haps-dev/1.0` | vivado(2026.1) + confpro_sx + **haps-tunnel** | Everyday HAPS-SX flow; ILA debug via hw_server |
| `haps-identify/1.0` | + synplify + identify + verdi | The Synopsys IICE/Identify FSDB debug route |
| `haps-tunnel/1.0` | (standalone) | The bench tunnel; loaded by both bundles, also usable alone |
| `haps-sx-tools/1.0` | *(existing, untouched)* | **Legacy** ProtoCompiler/ProtoSynthesis flow |

`haps-dev`, `haps-identify` and `haps-sx-tools` are **mutually exclusive** (`conflict`) — load one.

## Design (why it's shaped this way)
- **One tunnel module, one SSH ControlMaster, both forwards.** `-L 3121:localhost:3121`
  (JTAG → hw_server *on haps-dev*) and `-L 18000:haps-sx:18000` (ConfPro → the *board*,
  through haps-dev). **No `ExitOnForwardFailure`** — the board-side 18000 forward connects
  lazily, so a rebooting board must not drop the JTAG forward.
- **A UDP board-state relay beside the TCP forwards** (`bin/haps-state-relay`), because
  TCP 18000 *drives* a board but does not *display* one — see below.
- **Tunnel in each bundle but standalone**, so it is independently loadable and owns its teardown.
- **Unguarded `module load`** in the bundles (NOT the site `is-loaded` idiom, NOT `depends-on`
  which is verified absent on Modules 4.5.2): registers each as a *refcounted requirement*, so
  `module unload` auto-unloads the unneeded ones **and fires `haps-tunnel`'s remove hook**,
  closing the ControlMaster. This is the only construction giving clean "unload → tunnel closes".
- **Best-effort tunnel:** `timeout`+`BatchMode`+`ConnectTimeout`+`|| true`, so a `module load`
  from `.bashrc`/`make`/CI **never hangs or fails**; offline/no-key users still get the tools.
  `ControlPersist=10m` reaps a leaked master; the ref-count closes it promptly on the last unload.
  `HAPS_NO_TUNNEL=1` opts out; `HAPS_TUNNEL_SSH=host` uses a de-privileged account;
  `HAPS_ON_NET=1` keeps `CONFPRO_BOARD=haps-sx.haps-net` for anyone on the private segment.
- **No ProtoCompiler/VCS** (doesn't work with haps-sx). Vivado un-pinned → **site default 2026.1**,
  matching `hw_server 2026.1` on haps-dev. Verdi is loaded **explicitly** in `haps-identify`
  (it used to ride in via ProtoCompiler).

## Why a UDP relay (the grey-panel bug)

ConfPro-SX uses **two** channels, and `ssh -L` can only carry one:

| Channel | Carries | Tunnellable |
|---|---|---|
| **TCP 18000** | session/command — System, Power, Clock, Program, Reset | yes |
| **UDP 18009 out → 18008 back** | **all 25 board-state fields**, incl. `control`/`controller` | **no — `ssh -L` is TCP-only** |

The state channel is `SearchCABNet::touchBorad()`, which is what the GUI calls to refresh a
*manually added* board — i.e. exactly the seeded entry a tunnelled user has. `confpro-sx-shadow`
seeds `boardinfolist.json` with **6 identity fields** (`board id`, `active ip`, `board sn`,
`board name`, hardware/firmware version); the other **19 are state and arrive only over UDP**.

So on a tunnelled host the row appears and the board is drivable, but nothing describes it.
Measured 2026-08-26 from srv03335: probe from haps-dev → 795 bytes / 25 fields; from srv03335
→ timeout, both to `127.0.0.1` and to the board directly. Across three ConfPro logs, **20
searches from the tunnelled host produced 0 feedback datagrams**; the one session with the
board on the local /24 (08-05) produced 3.

**The dangerous part is not cosmetic.** `SystemSelectionDialog::addItem` paints a row grey and
labels it *Used* only when the UDP-sourced `control` flag is true — otherwise **white, "Idle"**.
And `on_selectButton_clicked` gates the *Board is Busy* popup on that same flag: false skips
the popup and proceeds straight to connect. With no UDP reply the flag is always false, so **a
board somebody else is holding looks free and the GUI connects to it anyway.**

> Earlier revisions of this README, of the `confpro_sx` modulefile, and of `confpro-sx-shadow`
> all stated that TCP 18000 is *all* the GUI needs once the board is in the list. That claim is
> **true of the CLI and false of the GUI** — verified by control: `Confpro-SX-Cmd` contains 0
> `SearchCABNet` symbols and 0 `QUdpSocket` imports, the GUI imports 6. So `confpro-program` /
> `fpga_config.sh` really do need only 18000; the GUI's state display, Used/Idle column and
> busy interlock do not work without UDP.

`bin/haps-state-relay` restores the channel with no VPN, tun device or root:

```
GUI --UDP--> 127.0.0.1:18009 (relay) --ssh--> haps-dev --UDP--> board:18009
GUI <--UDP-- 127.0.0.1:18008 (relay) <--ssh-- haps-dev <--UDP-- board:18008
```

Three details are load-bearing: it **never binds 18008** (the GUI holds it exclusively while its
dialog is open — the relay only `sendto()`s it); it replies **from `127.0.0.1:18009`**, reusing
the receiving socket, so the source matches the entry being refreshed; and it rewrites
**`active ip`** (and `host ip list`) to the local endpoint, because the GUI matches rows on
`board id` (MAC) and takes the address from the payload — relaying the board's own `10.60.1.10`
would redirect the GUI's TCP connection to an address with no route from here and break the
working path. It is driven from `bin/haps-tunnel` so it shares that script's ref-count, and it
fails open: no jump host, no key or no answer means the relay stays quiet and ConfPro behaves
exactly as it does today.

### What this does NOT fix

The grey **main window** is a separate, TCP-side symptom and this relay does not address it.
The logs show tunnelled sessions reaching `ConnectedState` → `Board Connected` → `enable gui
mode`, then 21 s of silence → `Connect Timeout` → `enable offline gui mode`, which is
`MainWindow::enableOfflineMode()` (a `resetBoardGui()` + `QTabWidget::clear()` + 14 ×
`setEnabled(false)`; Qt renders disabled widgets grey). The forward itself is sound — verified
end to end: a local connect to `127.0.0.1:18000` shows `10.60.1.1:34076 → 10.60.1.10:18000
ESTAB` on the jump host. **Why the board then goes quiet for 21 s is still open.**

What the relay fixes is the **System Selection** side: live board state, the Used/Idle column,
the User-IP label and the busy interlock. Treat the two as separate bugs.

### Known limits

- **One relay per host, one board.** It serves a single board (`HAPS_CONFPRO_RHOST`) at a
  single local endpoint, and refuses queries naming anything else rather than answering with
  the wrong board's identity. `127.0.0.1:18009` is host-global while the pidfile is per-user,
  so on a shared host the *second* user's `module load` finds the port held and says so; their
  GUI is then served by the first user's relay, over the first user's ssh credential, and goes
  quiet when that user unloads.
- **The board sees `10.60.1.1`** (`gw-haps`, the jump host's bench-lan address) for every
  tunnelled client, so the board's `controller` field cannot distinguish them. `haps-board-lock`
  decides "is this lock mine?" by matching that against local `hostname -I`, which can never
  match on a tunnelled host.
- Loopback only unless `HAPS_STATE_ALLOW_REMOTE=1`: a wider bind would be an unauthenticated
  ~×790 UDP reflector aimed at a fixed victim port.

It is also a usable shell tool where the GUI cannot reach the board at all:

```bash
haps-state-relay probe      # reachable=yes state=idle holder= held_by_confpro=no held_by_xvc=no
haps-state-relay status
```

## Deploy (CAD/IT — shared infra, do deliberately)
1. Copy `haps-tunnel/`, `haps-dev/`, `haps-identify/` into `/research/CAD/EDA-Modulefiles/tools/`.
2. `install -m 0755 bin/haps-tunnel bin/haps-state-relay /apps/synopsys/haps/haps-sx/bin/`
   (or the shared `SoC-Labs-HAPS-SX-Tools/bin/` clone; or set `HAPS_TUNNEL_BIN`).
   **Both**: `haps-tunnel` locates the relay beside itself, so installing one without the
   other silently returns the grey panel. Override with `HAPS_STATE_RELAY_BIN`.
3. **Recommended — de-privilege the SSH.** Create an unprivileged `jtag` account on haps-dev with
   a forward-only key:
   `command="",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="localhost:3121",permitopen="haps-sx:18000" ssh-ed25519 …`
   then set `HAPS_TUNNEL_SSH=<alias>` (default `haps-dev` = root works but isn't least-privilege).
   Note the relay runs a **command** (`python3 -u -c …`) rather than a forward, so a
   `command=""` restriction that permits only port-forwarding will disable board state.
   Give that key a `command=` wrapper that also accepts the relay's remote probe.
4. Bind `hw_server` on haps-dev to localhost (`-s tcp:127.0.0.1:3121`) so 3121 leaves the LAN.
5. Swap `fpga/haps-sx/Makefile`'s `module load haps-sx-tools` → `module load haps-dev`.
6. Optional: add reciprocal `conflict haps-dev` / `conflict haps-identify` to `haps-sx-tools/1.0`.

## User side (per client, e.g. srv03335 / srv04936)
A key in your own account on haps-dev (the `jtag` account of Deploy step 3 does not exist
yet) + a `Host haps-dev` block in `~/.ssh/config` naming that account. Off-LAN
hosts reach hw_server only via this tunnel — which is the sanctioned path. Then `module load haps-dev`.
