# SSH Port Forwarding, SOCKS & Multi-Hop Tunneling, In Depth

A complete guide to SSH port forwarding (`-D`/`-L`/`-R`), SOCKS proxy chaining,
jump hosts, and related tunneling, so you can reach private networks that are
only accessible from a remote host (e.g. a bastion).

**Scenario:** Your laptop runs Linux. You want to open your local browser and
reach resources that live only on a remote network, by hopping through one or
more intermediate Linux hosts:

```
laptop ──> devbox ──> bastion ──> bastion2 ──> private network
```

---

## Table of Contents

1. [The Core Concept: Where the Proxy Exits](#1-the-core-concept-where-the-proxy-exits)
2. [How a Socket Listener Works](#2-how-a-socket-listener-works)
3. [Solution A: ProxyJump (Recommended)](#3-solution-a-proxyjump-recommended)
4. [ProxyCommand & netcat-style Relays](#4-proxycommand--netcat-style-relays)
5. [Solution B: Manual Nested Tunnels](#5-solution-b-manual-nested-tunnels)
6. [Adding More Hops (4+ Host Chains)](#6-adding-more-hops-4-host-chains)
7. [Reverse Forwarding (`-R`)](#7-reverse-forwarding--r)
8. [DNS and Proxy DNS (SOCKS5 vs SOCKS5h)](#8-dns-and-proxy-dns-socks5-vs-socks5h)
9. [Configuring Clients (Browser & Other Apps)](#9-configuring-clients-browser--other-apps)
10. [Verifying the Tunnel with curl](#10-verifying-the-tunnel-with-curl)
11. [What Happens When You SSH (Shell Execution)](#11-what-happens-when-you-ssh-shell-execution)
12. [Closing the Tunnel](#12-closing-the-tunnel)
13. [Keepalives, Resilience & Auto-Reconnect](#13-keepalives-resilience--auto-reconnect)
14. [Security Model & Trust](#14-security-model--trust)
15. [Performance, MTU & sshuttle](#15-performance-mtu--sshuttle)
16. [When to Use What (Decision Guide)](#16-when-to-use-what-decision-guide)
17. [IPv6 Notes](#17-ipv6-notes)
18. [Troubleshooting Common Errors](#18-troubleshooting-common-errors)
19. [Windows End-to-End Worked Example](#19-windows-end-to-end-worked-example)
20. [Complete, Ready-to-Paste ~/.ssh/config](#20-complete-ready-to-paste-sshconfig)
21. [Quick Reference / Cheat Sheet (per OS)](#21-quick-reference--cheat-sheet-per-os)
22. [Glossary](#22-glossary)

---

## 1. The Core Concept: Where the Proxy Exits

When you run:

```bash
ssh -D 11443 devbox
```

SSH does three things:

1. Opens a normal encrypted SSH connection from your **laptop** to **devbox**.
2. Starts a **SOCKS proxy server listening on `127.0.0.1:11443` on your laptop**.
3. Any app (your browser) that sends traffic to that SOCKS port gets it
   tunneled through the SSH connection and **emitted onto the network from
   devbox**.

So the **exit point** is devbox. Your browser effectively *becomes devbox* on
the network. You can reach anything devbox can reach but **nothing that only
bastion can reach**.

> **The single most important idea in this whole document:**
> The SOCKS *listener* stays on your laptop (so the browser can use
> `127.0.0.1:11443`), but the *exit point* is wherever the SSH session
> terminates. To reach a deeper network, you must push the **exit point** one
> hop further, to the host that can actually see that network.

```
            SOCKS listener                              exit point
                  │                                         │
   [ Laptop ] ────┴──── ssh ────> [ devbox ] ──── ssh ────> [ bastion ] ──> private network
   127.0.0.1:11443
```

| What you run | Exit point | Reaches bastion's network? |
|---|---|---|
| `ssh -D 11443 devbox` | devbox | No, only devbox's network |
| `ssh -D 11443 -J devbox bastion` | **bastion** | Yes |
| Nested `-D` on devbox + `-L` from laptop<br>**①** `ssh -D 1080 bastion -N` *(run on devbox)*<br>**②** `ssh -L 11443:127.0.0.1:1080 devbox -N` *(run on laptop)* | **bastion** | Yes |

The third row is the manual two-step method covered in
[Solution B](#5-solution-b-manual-nested-tunnels): you first stand up a SOCKS
proxy **on devbox** that exits at bastion (`-D 1080`), then pull that proxy
port back to your laptop with a local forward (`-L 11443:127.0.0.1:1080`). Your
browser still talks to `127.0.0.1:11443`, but traffic ultimately exits at
bastion, identical end result to the `-J` one-liner above.

### The full 4-host chain, with encryption boundaries

When you chain `laptop → devbox → bastion → bastion2`, every leg is wrapped in
the leg before it, like nested envelopes. With `ProxyJump` the SSH session is
**end-to-end** from your laptop to the final host, so each intermediate hop only
ever relays bytes that are *already encrypted for the hop beyond it*:

```
Wire path:  [LAPTOP] ──► devbox ──► bastion ──► bastion2 ──► wiki.internal:443
             SOCKS on     (relay)    (relay)    (EXIT: resolves DNS,
          127.0.0.1:11443                         opens the real TCP)

Encryption layers, outermost → innermost.
Each hop can peel only its OWN outer layer; everything beneath is opaque to it:

  layer 1   SSH  laptop ⇄ devbox     ── devbox sees only ciphertext beneath
   layer 2   SSH  laptop ⇄ bastion    ── bastion sees only ciphertext beneath
    layer 3   SSH  laptop ⇄ bastion2   ── the EXIT; the SOCKS stream rides inside here
     layer 4   TLS  browser ⇄ wiki      ── HTTPS payload; even bastion2 can't read it
```

- **devbox** sees an encrypted stream to bastion (it can't read it); it just
  forwards the `-W` channel onward.
- **bastion** likewise sees only the encrypted stream to bastion2.
- **bastion2** is the **exit point**: it terminates the SOCKS proxy, resolves
  your hostnames (with remote DNS), and makes the real outbound TCP connection.
- The browser↔destination TLS (if any) is *another* layer inside all of this,
  so even bastion2 can't read HTTPS payloads (see [Section 14](#14-security-model--trust)).

---

## 2. How a Socket Listener Works

A **socket** is an OS-level communication endpoint identified by the tuple
`(protocol, IP address, port)`, e.g. `(TCP, 127.0.0.1, 11443)`. The OS exposes
it to programs as a **file descriptor** (an integer handle), because on Unix
"everything is a file."

### The listening socket lifecycle (BSD sockets API)

```
socket()  → create the endpoint (returns an fd)
bind()    → attach it to an address + port, e.g. 127.0.0.1:11443
listen()  → mark it passive; the kernel now queues incoming connections
accept()  → pull one established connection off the queue → a NEW socket fd
```

Key points:

- **The bind address matters.** Binding to `127.0.0.1` (loopback) means *only
  processes on your laptop* can connect. Binding to `0.0.0.0` would expose the
  port to your entire LAN. This is why we bind the SOCKS proxy to
  `127.0.0.1:11443`. (To deliberately share the proxy with other machines you
  can pass `-D 0.0.0.0:11443` and set `GatewayPorts yes`, but that is a
  security trade-off; anyone on your LAN could then use your tunnel.) The IPv6
  loopback equivalent is `[::1]`,  note the **brackets**, required so the colon
  before the port isn't ambiguous (see [Section 17](#17-ipv6-notes)).
- **`listen()` creates a backlog queue.** Incoming TCP handshakes
  (SYN / SYN-ACK / ACK) complete and wait in a kernel queue until the program
  calls `accept()`. The queue depth is the *backlog* argument to `listen()`.
- **`accept()` returns a *new, separate* socket** for each client. The
  listening socket keeps listening; the new socket is the data pipe for that
  one conversation. One listener can therefore serve many simultaneous
  connections, each with its own fd.
- After accept, the program **relays bytes** between sockets in a loop, usually
  using `select`/`poll`/`epoll`/`kqueue` to watch many descriptors at once
  without blocking on any single one.
- **"Everything is a file" is a Unix idea.** Because the OS hands the socket
  back as a file descriptor, the same `read()`/`write()`/`close()` calls that
  work on files also work on sockets. This is what lets ssh multiplex the
  listener and every accepted connection in one event loop. As you'll see
  below, this assumption is exactly what changes on Windows.

### Does this differ on macOS or Windows?

The *concepts* above (SOCKS listener on your laptop, exit point at the far SSH
host) are identical on every OS, only the **plumbing underneath and the
tooling around it** changes.

**macOS is essentially identical to Linux.** macOS is a Unix (its network stack
descends directly from BSD, the origin of the "BSD sockets" API). Sockets are
real file descriptors, "everything is a file" holds, and it ships the same
OpenSSH client. Every command in this guide works verbatim. The only practical
differences are the *introspection tools*: macOS has no `ss`; use
`lsof -i :11443` or `netstat -an | grep 11443`, and `pgrep -af "ssh -N"` /
`kill` work the same. **Throughout this guide, "Unix" means Linux *and* macOS**;
they differ only in those few inspection commands.

**Windows use the same protocol but different internals.** Modern Windows 10/11 ships
OpenSSH, so `ssh -D 11443 devbox -N` works unchanged in PowerShell or
`cmd.exe`, and your browser still points at `127.0.0.1:11443`. But underneath:

- Sockets are **Winsock** (`ws2_32.dll`) objects, not Unix file descriptors.
  "Everything is a file" does **not** apply in Windows. A socket is its own kind of
  kernel handle, distinct from file `HANDLE`s, and you generally cannot mix it
  into the same `select()`/`epoll` loop as ordinary files. Winsock mirrors the
  BSD `socket()`/`bind()`/`listen()`/`accept()` calls, but high-performance
  servers use `WSAPoll`/IOCP rather than `epoll`/`kqueue`. (ssh handles all of
  this internally; it matters only if you're writing the code.)
- **Finding and killing the tunnel uses different tools.** There is no
  `ss`/`lsof`/`pgrep`. Use instead:

```powershell
netstat -ano | findstr 11443           # show the listener + owning PID
Get-NetTCPConnection -LocalPort 11443  # PowerShell-native equivalent
taskkill /PID <pid> /F                 # kill it (or Stop-Process -Id <pid>)
```

- **Classic alternative: PuTTY / `plink`.** Before built-in OpenSSH, Windows
  users created tunnels with PuTTY (Connection → SSH → Tunnels: "Dynamic" for
  `-D`, "Local" for `-L`) or scripted them with `plink -D 11443 devbox`. These
  still work and behave the same on the wire.
- **`~/.ssh/config` lives at `%USERPROFILE%\.ssh\config`** and `ControlMaster`
  multiplexing ([Section 12](#12-closing-the-tunnel)) is **not supported** by
  Windows OpenSSH, because it relies on Unix-domain control sockets. On Windows,
  manage tunnels by PID. A full Windows walkthrough is in
  [Section 19](#19-windows-end-to-end-worked-example).

### How this maps to `ssh -D` / `DynamicForward`

When you start a dynamic forward, **the ssh client itself becomes a SOCKS proxy
server** on your laptop:

1. ssh calls `socket()` / `bind()` / `listen()` on `127.0.0.1:11443`.
2. Your browser connects → ssh `accept()`s a new socket.
3. ssh reads the **SOCKS handshake** off that socket. The handshake tells ssh
   *where the browser actually wants to go* (e.g. `wiki.internal:443`).
4. ssh does **not** open a new TCP/IP connection from your laptop. Instead it
   opens a new **SSH channel** multiplexed over the *single existing encrypted
   SSH connection* and asks the remote `sshd` (at the exit host) to open a TCP
   connection to `wiki.internal:443`.
5. Bytes are relayed:
   `browser ↔ laptop socket ↔ (SSH channel) ↔ exit host ↔ destination`.

This is why one SSH connection can carry dozens of browser tabs at once, each
becomes its own **channel** inside the one TCP connection.

```
  browser ──TCP──> [127.0.0.1:11443 listener]
                         │  (ssh client = SOCKS server)
                         │  one SSH connection, many channels
                         ▼
                    exit host's sshd ──TCP──> wiki.internal:443
```

### How this maps to `ssh -L` / `LocalForward`

`-L` (local forwarding) uses the **exact same listener machinery** as `-D`,
`socket()` / `bind()` / `listen()` / `accept()` on a port on your laptop, but
with one crucial difference in what happens *after* `accept()`:

| | `-D` (dynamic / SOCKS) | `-L` (local / static) |
|---|---|---|
| Destination | chosen **per connection** by the client via a SOCKS handshake | **fixed** at launch in the flag itself |
| Listener speaks | the SOCKS5 protocol | nothing, it's a dumb byte pipe |
| Use it for | a browser hitting *many* hosts | one *specific* host:port |

The syntax is:

```bash
ssh -L [bind_addr:]local_port:dest_host:dest_port  sshhost
```

When you run, say, `ssh -L 8080:wiki.internal:443 devbox -N`:

1. ssh `bind()`/`listen()`s on `127.0.0.1:8080` on your **laptop**.
2. Any app connects to `127.0.0.1:8080` → ssh `accept()`s a new socket.
3. ssh opens an **SSH channel** over the existing connection and asks
   **devbox's sshd** to open a TCP connection to `wiki.internal:443`.
4. Bytes are relayed:
   `app ↔ laptop:8080 ↔ (SSH channel) ↔ devbox ↔ wiki.internal:443`.

Two things to internalize:

- **`dest_host:dest_port` is resolved and reached *from the SSH server's
  vantage point* (the exit host), not your laptop's.** That's why `-L` can
  reach hosts your laptop can't, the same reason `-D` works.
- **`dest_host` is often `127.0.0.1`.** In the nested method from Section 1/5,
  `ssh -L 11443:127.0.0.1:1080 devbox` means "forward my local `11443` to the
  port `1080` *on devbox itself*, which is precisely where the inner SOCKS
  proxy is listening. SOCKS is just a TCP stream, so `-L` happily carries it.

```
  app ──TCP──> [127.0.0.1:8080 listener]
                     │  (ssh client = plain relay, no SOCKS)
                     │  one SSH channel, one fixed destination
                     ▼
                devbox's sshd ──TCP──> wiki.internal:443
```

The config-file equivalent of `-L` is `LocalForward`:

```sshconfig
Host devbox
    LocalForward 127.0.0.1:8080 wiki.internal:443
```

(The mirror image, a listener on the *remote* side forwarding back to your
laptop, is `-R`, covered in [Section 7](#7-reverse-forwarding--r).)

---

## 3. Solution A: ProxyJump (Recommended)

`ProxyJump` (`-J`) tells your laptop to transparently use an intermediate host
as a *jump host*. The actual SSH session terminates at the **final** host, so
the `-D` SOCKS proxy also exits there.

### Command line

```bash
ssh -D 11443 -J devbox bastion -N
```

- `-D 11443`: SOCKS proxy on your laptop at `127.0.0.1:11443`.
- `-J devbox`: reach bastion *through* devbox.
- `bastion`: the final host; traffic exits here.
- `-N`: don't run a remote shell/command, just hold the tunnel open. This is
  critical when a broken remote shell RC file would kill an interactive login
  (see [Section 11](#11-what-happens-when-you-ssh-shell-execution)).

This works even if **bastion is only reachable from devbox** (the usual reason
a bastion exists). Your laptop only needs to reach devbox; devbox needs to
reach bastion.

### How ProxyJump works under the hood

`-J devbox` is shorthand for `-o ProxyJump=devbox`, which runs
`ssh -W bastion:22 devbox`. The `-W host:port` flag forwards your local
stdin/stdout straight to `host:port` on the next hop. The encryption is
**nested / end-to-end**: your laptop establishes a real SSH session with
bastion, and devbox only sees opaque encrypted bytes; it cannot read your
traffic.

### Nitty-gritty: a real `-vvv` jump trace

Run the command with `-vvv` and you can watch each layer being built. Trimmed
to the interesting lines:

```text
$ ssh -vvv -N -D 11443 -J devbox bastion
debug1: Executing proxy command: exec ssh -l youruser -vvv -W '[bastion]:22' devbox
debug1: Connecting to devbox [203.0.113.10] port 22.
debug1: Connection established.
debug1: Authenticating to devbox:22 as 'youruser'
debug1: Authentication succeeded (publickey).
debug1: channel 0: new [client-session]               # the -W channel on devbox
debug1: Requesting [email protected]
debug1: Connecting to bastion [198.51.100.20] port 22.  # opened FROM devbox
debug1: Authenticating to bastion:22 as 'youruser'
debug1: Authentication succeeded (publickey).           # end-to-end laptop⇄bastion
debug1: Local connections to LOCALHOST:11443 forwarded to remote address socks:0
debug1: Local forwarding listening on 127.0.0.1 port 11443.
debug1: channel 1: new [port listener]                  # the SOCKS listener
debug1: Entering interactive session.
```

Read it top-down: ssh first runs an **inner ssh** as the proxy command
(`-W [bastion]:22 devbox`), authenticates to **devbox**, then authenticates
**again to bastion** *over that channel* (proving the session is end-to-end),
and only then binds the SOCKS listener on `127.0.0.1:11443`.

---

## 4. ProxyCommand & netcat-style Relays

`ProxyJump` is modern syntactic sugar over the older, more general
**`ProxyCommand`** mechanism. Understanding `ProxyCommand` lets you tunnel
through things that aren't plain SSH jump hosts, HTTP `CONNECT` proxies, SOCKS
proxies, or relays built from `nc`/`ncat`/`socat`.

### The idea

`ProxyCommand` tells ssh: *"don't open a TCP socket to the target yourself, instead run this command, and use its **stdin/stdout** as the byte pipe to the
SSH server."* ssh speaks the SSH protocol over that pipe. The tokens `%h` and
`%p` expand to the target host and port.

### The three common forms

```sshconfig
# 1. Modern, preferred; identical to `ProxyJump devbox`:
Host bastion
    ProxyCommand ssh -W %h:%p devbox

# 2. Classic netcat relay (for ancient clients with no -W support):
Host bastion
    ProxyCommand ssh devbox nc %h %p

# 3. Through a SOCKS proxy you already built (`-D 11443`):
Host deep-host
    ProxyCommand nc -X 5 -x 127.0.0.1:11443 %h %p

# 4. Through an HTTP CONNECT proxy (corporate egress proxy):
Host bastion
    ProxyCommand nc -X connect -x proxy.corp:3128 %h %p
```

What each does:

- **Form 1 (`-W`)** is what `-J` runs internally. No helper binary needed on the
  jump host, and the SSH session stays end-to-end encrypted. **Prefer this.**
- **Form 2 (`nc`)** SSHes into devbox and runs `nc %h %p` *there* to open a
  plain TCP connection onward; your laptop then runs SSH over that pipe.
  Encryption is still end-to-end (it's SSH-inside-SSH, so devbox sees only
  ciphertext), but it **requires `nc` installed on devbox** and adds overhead.
  Only needed for clients too old for `-W` (pre-OpenSSH 5.4); rare today.
- **Form 3** routes the *SSH connection itself* through your SOCKS proxy. Handy
  when an internal host is only reachable *after* you've stood up the SOCKS
  tunnel; you can now `ssh deep-host` and it dials out through `127.0.0.1:11443`.
  `-X 5` selects SOCKS5; `-X 4` is SOCKS4; `-x` gives the proxy address.
- **Form 4** punches out through an HTTP forward proxy that only allows
  `CONNECT` (common on locked-down corporate networks). `nc -X connect` is
  OpenBSD `nc`; equivalents are `ncat --proxy proxy:3128 --proxy-type http %h %p`
  or `corkscrew proxy 3128 %h %p`.

> **`nc` portability warning:** there are several `netcat` implementations and
> their flags differ. `-X`/`-x` are **OpenBSD `nc`** (default on macOS and most
> Linux). The GNU `netcat` and Nmap's `ncat` use different syntax (`ncat
> --proxy`). Check `man nc` on the relay host. `socat` is a more powerful,
> consistent alternative: `ProxyCommand socat - PROXY:proxy.corp:%h:%p,proxyport=3128`.

### Nitty-gritty: watching a netcat ProxyCommand

```text
$ ssh -vvv -o 'ProxyCommand=ssh devbox nc %h %p' bastion
debug1: Executing proxy command: exec ssh devbox nc bastion 22
debug1: permanently_drop_suid: ...
debug1: identity file /home/you/.ssh/id_ed25519 type 3
debug1: Local version string SSH-2.0-OpenSSH_9.6
debug1: Remote protocol version 2.0, remote software version OpenSSH_9.6  # <- this is BASTION's sshd
debug1: Authenticating to bastion:22 as 'youruser'
debug1: Authentication succeeded (publickey).
```

Notice the proxy command (`ssh devbox nc bastion 22`) runs first, and the
"Remote protocol version" line reports **bastion's** sshd banner, proof your
client negotiated SSH all the way to bastion, with devbox merely shuttling bytes
via `nc`.

---

## 5. Solution B: Manual Nested Tunnels

Use this only if `ProxyJump` is unavailable (very old SSH), or you must do the
two-step manually. It uses two tunnels.

**Stage 1: on devbox**, create a SOCKS proxy that exits at bastion:

```bash
# Run this FROM devbox
ssh -D 1080 bastion -N
```

This makes a SOCKS proxy on **devbox at `127.0.0.1:1080`** whose traffic exits
at **bastion**.

**Stage 2: on your laptop**, forward your local port `11443` to devbox's
SOCKS port `1080`:

```bash
# Run this FROM the laptop
ssh -L 11443:127.0.0.1:1080 devbox -N
```

Now the path is:

```
browser → laptop:11443 → (SSH) → devbox:1080 (SOCKS) → (SSH) → exit at bastion
```

SOCKS is just a protocol spoken over a TCP stream, so tunneling devbox's SOCKS
port back to your laptop with `-L` works perfectly. The result is identical to
Solution A.

---

## 6. Adding More Hops (4+ Host Chains)

`ProxyJump` accepts a **comma-separated chain**, evaluated left-to-right. Each
host is reached *through* the one before it. The SOCKS proxy always exits at
the **final** host.

### Command line

```bash
ssh -D 11443 -J devbox,bastion bastion2 -N
```

Reads as: "connect to bastion2, jumping through devbox then bastion." The SOCKS
proxy on your laptop now exits at **bastion2**.

### Config form (chain the ProxyJumps)

Define each host pointing at its predecessor, so `ssh bastion2` automatically
builds the entire chain:

```sshconfig
Host devbox
    HostName devbox.example.com
    User youruser

Host bastion
    HostName bastion.internal          # resolved from devbox's view
    User youruser
    ProxyJump devbox

Host bastion2
    HostName bastion2.deep             # resolved from bastion's view
    User youruser
    ProxyJump bastion                  # which itself jumps through devbox
    DynamicForward 127.0.0.1:11443     # SOCKS exits HERE, at bastion2
    ExitOnForwardFailure yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Then:

```bash
ssh -N bastion2     # builds laptop→devbox→bastion→bastion2; SOCKS exits at bastion2
```

### Important nuances

- Each `HostName` is resolved **from the perspective of the hop that initiates
  that leg**, not from your laptop. `bastion2.deep` is resolved by bastion.
- Each hop only needs to reach the *next* hop on port 22.
- The encryption stays end-to-end: intermediate hops relay encrypted bytes and
  cannot read your traffic. (See the nested-envelope diagram in
  [Section 1](#1-the-core-concept-where-the-proxy-exits).)

---

## 7. Reverse Forwarding (`-R`)

`-R` is the **mirror image of `-L`**. Instead of opening a listener on your
laptop that reaches *into* the remote network, it opens a listener **on the
remote (SSH server) side** that reaches *back out* to a destination your
**laptop** can see.

### Syntax and direction

```bash
ssh -R [bind_addr:]remote_port:dest_host:dest_port  sshhost
```

Compare the two directions carefully, this is the part people get backwards:

| | `-L` (local forward) | `-R` (remote forward) |
|---|---|---|
| Listener lives on | your **laptop** | the **remote** sshhost |
| `dest_host:dest_port` resolved from | the **remote** host's view | your **laptop's** view |
| Traffic flows | laptop → into remote network | remote → back to laptop's network |

### Example: expose a local dev server to bastion

```bash
# Your laptop runs a web app on localhost:3000.
ssh -R 8080:localhost:3000 bastion -N
```

Now anything on **bastion** that connects to `127.0.0.1:8080` is piped back
through the SSH connection to your laptop's `localhost:3000`:

```
  process on bastion ──TCP──> [bastion 127.0.0.1:8080 listener]
                                     │  (sshd on bastion = relay)
                                     │  SSH channel back to your laptop
                                     ▼
                            your laptop's ssh ──TCP──> localhost:3000
```

### Key points & gotchas

- **By default the remote listener binds to `127.0.0.1` on the server**, so only
  processes *on* bastion can use it. To expose it on bastion's external
  interface (so other machines on bastion's network can reach it), the server's
  `sshd_config` must set `GatewayPorts yes` (or `clientspecified`), and you bind
  `-R 0.0.0.0:8080:...`. Treat this as exposing your laptop's service to that
  whole network, a real security decision.
- **Remote *dynamic* (reverse SOCKS):** OpenSSH 7.6+ supports `ssh -R 1080
  sshhost` with no destination, which makes the **server** a SOCKS proxy whose
  traffic exits via **your laptop**. It's the exact inverse of `-D`: the exit
  point becomes your laptop instead of the bastion.
- **Common uses:** share a local service for a quick demo, receive a
  webhook/callback on a machine behind NAT, give a remote build host temporary
  access to something only your laptop can reach, or a (carefully authorized)
  reverse shell for NAT traversal.
- It works through a jump chain too: `ssh -R 8080:localhost:3000 -J devbox bastion`.

---

## 8. DNS and Proxy DNS (SOCKS5 vs SOCKS5h)

### Normal DNS

DNS turns a name (`wiki.internal`) into an IP (`10.4.2.7`). Your laptop resolves
names through its **local resolver**: it checks `/etc/hosts`, then asks the
nameservers in `/etc/resolv.conf` (often via `systemd-resolved`, governed by
`/etc/nsswitch.conf`). Those nameservers are *your laptop's*, typically your
home router or ISP.

### The problem with internal hosts

Bastion-network resources usually have **private names** that:

- your laptop's resolver doesn't know at all (returns `NXDOMAIN`), or
- resolve to the **wrong** IP because of **split-horizon DNS** (the same name
  resolves differently inside vs. outside the private network).

If your browser resolves `wiki.internal` *locally* first and then hands the IP
to the proxy, you've already failed; either no answer, or the wrong/public IP.

### Proxy DNS / remote DNS (the `h` in SOCKS5h)

The SOCKS5 protocol has an address-type field (`ATYP`) in its connect request.
It can be:

- `0x01` = an IPv4 address (client already resolved the name),
- `0x03` = a **literal domain name** (let the proxy resolve it), or
- `0x04` = an IPv6 address.

**"Proxy DNS" means the client sends the hostname (`ATYP=0x03`) instead of an
IP**, so the DNS lookup happens at the **exit host**, which sits on the network
where that name actually resolves correctly. Because the exit host does the
lookup, it also returns the right record family; including **AAAA (IPv6)**
records for IPv6-only internal hosts (see [Section 17](#17-ipv6-notes)).

| Scheme | Who resolves DNS | Use when |
|---|---|---|
| `socks5`  | your laptop (local)        | name is publicly resolvable |
| `socks5h` | the proxy / exit host (remote) | internal / split-horizon names |

Bonus: remote DNS also prevents **DNS leaks**; your laptop never queries the
outside world for those internal names.

---

## 9. Configuring Clients (Browser & Other Apps)

Point your client at SOCKS5 `127.0.0.1:11443` **and enable remote DNS** so
internal hostnames resolve at the exit host.

### Firefox (best choice: true per-application proxy)

- Settings → Network Settings → Manual proxy configuration
- SOCKS Host: `127.0.0.1`   Port: `11443`   → select **SOCKS v5**
- Check **"Proxy DNS when using SOCKS v5"**
- Equivalent in `about:config`: `network.proxy.socks_remote_dns = true`

### Chrome / Chromium (resolves DNS remotely over SOCKS5 automatically)

```bash
google-chrome --user-data-dir=/tmp/socks-profile \
  --proxy-server="socks5://127.0.0.1:11443"
```

Use a separate `--user-data-dir` so it doesn't disturb your normal browsing
profile.

### Apps that don't speak SOCKS (`proxychains`)

Many CLI tools (`psql`, `redis-cli`, a custom binary) have no proxy setting.
Two ways to push them through the tunnel anyway:

- **`ALL_PROXY` env var**: many tools (curl, anything using libcurl, some Go
  apps) honor it:

```bash
ALL_PROXY=socks5h://127.0.0.1:11443 some-tool   # socks5h = remote DNS
```

- **`proxychains-ng`** (Linux/macOS): intercepts a program's `connect()` calls
  via an `LD_PRELOAD` shim and reroutes them through the SOCKS proxy:

```bash
# ~/.proxychains/proxychains.conf  (or /etc/proxychains4.conf)
proxy_dns                 # resolve names at the proxy (the socks5h behaviour)
[ProxyList]
socks5 127.0.0.1 11443
```

```bash
proxychains4 psql -h db.internal -U app
```

> **Caveat:** `proxychains` hooks libc, so it **cannot** redirect
> statically-linked binaries (many Go programs); their syscalls bypass the
> shim. For those, rely on the program's native proxy support / `ALL_PROXY`, or
> use a transparent solution like `sshuttle` ([Section 15](#15-performance-mtu--sshuttle)).

---

## 10. Verifying the Tunnel with curl

```bash
curl --socks5-hostname 127.0.0.1:11443 https://ifconfig.me
```

`--socks5-hostname` = "use a SOCKS5 proxy at `127.0.0.1:11443`, **and resolve
the hostname at the proxy**" (curl's name for socks5**h**). Step by step:

1. **curl connects to `127.0.0.1:11443`**, the listening socket your ssh
   client opened. (No DNS needed; it's a literal IP.)
2. **SOCKS5 handshake:**
   - curl sends a greeting: SOCKS version `5` + supported auth methods.
   - ssh replies: version `5` + "no authentication."
   - curl sends a **CONNECT request**: `ATYP=0x03`, domain = `ifconfig.me`,
     port = `443`. It sends the *name*, not an IP; that's the `-hostname` part.
3. **ssh relays the request through the tunnel chain** to the exit host's
   `sshd`. The **exit host resolves `ifconfig.me`** (remote DNS) and opens a TCP
   connection to it on port 443.
4. ssh replies to curl: "connection established." The SOCKS tunnel is now a
   transparent byte pipe.
5. **TLS happens end-to-end** between curl and `ifconfig.me`. The proxy / exit
   host only relays **encrypted** bytes; it cannot read the HTTPS content.
   SOCKS operates at the TCP layer, *below* TLS.
6. curl sends `GET /` over HTTPS. The `ifconfig.me` server reports back **the
   source IP it sees**, which is the **exit host's egress IP**, because that's
   the machine that actually made the outbound TCP connection.

So the printed IP being the exit host's IP **proves traffic exits where you
intended**, and the fact that `ifconfig.me` resolved at all (with `-hostname`)
proves remote DNS works. It's the perfect one-line sanity check for the chain.

### Nitty-gritty: the SOCKS5 handshake on the wire

Add `-v` and curl narrates the handshake and where DNS happened:

```text
$ curl -v --socks5-hostname 127.0.0.1:11443 https://ifconfig.me
*   Trying 127.0.0.1:11443...
* SOCKS5 communication to ifconfig.me:443
* SOCKS5 connect to ifconfig.me:443 (remotely resolved)   # <- ATYP=0x03, remote DNS
* SOCKS5 request granted.
* Connected to 127.0.0.1 (127.0.0.1) port 11443
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384   # <- TLS is end-to-end
*  subject: CN=ifconfig.me
> GET / HTTP/2
> Host: ifconfig.me
> user-agent: curl/8.5.0
>
< HTTP/2 200
< content-type: text/plain
<
198.51.100.42                                             # <- the EXIT host's egress IP
* Connection #0 to host 127.0.0.1 left intact
```

The two lines that matter: **"(remotely resolved)"** confirms the name was sent
to the proxy (no DNS leak), and the returned body **`198.51.100.42`** is the
exit host's public IP, not your laptop's, proving traffic exits where you
intended while TLS stayed private end-to-end.

---

## 11. What Happens When You SSH (Shell Execution)

Every command in this guide (`ssh -N`, `scp`, `ProxyJump`, `-D`) ultimately
depends on what **sshd on the remote host actually runs** after authentication.
Understanding that path explains why a broken `.zshrc` can lock you out of an
interactive shell while a SOCKS tunnel still comes up, and why "just run bash
instead" often does not help.

### The problem (a real incident)

A user added `exit` to their `.zshrc`. After that, **every SSH login dropped
immediately**. They tried to bypass the RC files:

```bash
ssh -vvv your_devbox -t "bash --noprofile --norc"
ssh -vvv your_devbox -t "/bin/sh"
```

Both still failed. Why?

### What sshd actually executes

After you authenticate, **sshd** looks up your account in `/etc/passwd` and
reads the **`SHELL` field**, your **login shell** (e.g. `/bin/zsh`). What
happens next depends on whether you asked for a remote command.

**Interactive login** (plain `ssh host`):

```
sshd  →  exec your login shell  (/bin/zsh)
       →  zsh reads startup files (.zshenv, .zprofile, .zshrc, …)
       →  you get a prompt (or `exit` in .zshrc kills the session instantly)
```

**Remote command** (`ssh host some-command`):

```
sshd  →  exec login_shell -c "some-command"
       →  e.g.  /bin/zsh -c "bash --noprofile --norc"
```

The command you typed is **not** executed directly by sshd. It is passed as an
argument to **your login shell**. That shell's startup files still run *before*
your command, unless you carefully avoid them (see below).

**No remote command** (`ssh -N host`, or `-N` combined with `-D`/`-L`/`-R`):

```
sshd  →  authenticated session with no shell, no command
       →  only port forwards / subsystems requested by the client
```

OpenSSH **does not spawn your login shell** for `-N`. The session exists purely
to hold forwards open. This is why `ssh -N -D 11443 bastion` keeps working
even when interactive login is broken.

### Nitty-gritty: strace on a remote command

Attach `strace` to the shell sshd spawns and you can see the chain:

```text
[pid 6604] execve("/bin/zsh", ["zsh", "-c", "sh"], 0x555b4ce16050 /* 12 vars */) = 0
[pid 6604] execve("/usr/bin/sh", ["sh"], 0xffb99c0 /* 16 vars */) = 0
```

Read it as:

1. sshd starts **`/bin/zsh`** (from `/etc/passwd`), not `sh`.
2. zsh is invoked with **`-c "sh"`**, your remote command is an argument to zsh.
3. Only after zsh's startup logic runs does it exec **`sh`**.

If step 2 hits `exit` in a startup file, step 3 never happens.

### Which startup files run (and when bypass attempts fail)

Shells differ, but the pattern is the same: **some RC files run even for
`-c` commands**, and SSH almost never skips your login shell entirely.

| Shell | Always read (even `shell -c cmd`) | Read for login / interactive only |
|---|---|---|
| **zsh** | `/etc/zshenv`, `~/.zshenv` | `.zprofile`, `.zshrc`, `.zlogin` (login/interactive) |
| **bash** | often `/etc/profile` if login (`-l`) | `~/.bash_profile`, `~/.bashrc` (depends on `-l` / `-i`) |
| **sh** / dash | minimal | depends on how sshd invokes it |

So when someone puts `exit` in **`.zshrc`**, a plain `zsh -c '…'` might
survive, but if sshd invokes a **login** shell, or the `exit` is in
**`.zshenv`** (which zsh reads on *every* invocation), bypass attempts like
`bash --noprofile --norc` still die **inside zsh before bash starts**.

That is why `ssh host -t "bash --noprofile --norc"` did not help: sshd ran
`/bin/zsh -c "bash --noprofile --norc"`, zsh loaded the file containing
`exit`, and the session ended.

### What each SSH option does on the remote side

| What you run | Remote shell spawned? | Login / RC files | Forwards / tunnel still work? |
|---|---|---|---|
| `ssh host` | Yes, interactive login shell | Yes, full startup | N/A (you need a working shell) |
| `ssh -N host` | **No**, no command, no shell | **No** RC files | **Yes**, `-D`/`-L`/`-R` bind on laptop |
| `ssh -N -D 11443 -J devbox bastion` | **No** on bastion (final host) | **No** | **Yes**, this guide's main pattern |
| `ssh host command` | Yes; `login_shell -c "command"` | **Often yes** (at least `.zshenv`) | Only if the command completes; `exit` in RC kills it |
| `ssh -t host "bash --noprofile --norc"` | Yes, `zsh -c "bash …"` | **Yes**, zsh RC runs first | **No** if RC exits first |
| `ssh -T host` | Like above but **no TTY** | Same RC rules | Same |
| `scp file host:` (legacy scp) | Yes, `login_shell -c "scp -t …"` | **Yes**, same RC trap | **No** if RC exits |
| `scp -s file host:` / SFTP | **No user shell**, `sftp-server` subsystem | **No** RC files | **Yes**, file transfer still works |
| `sftp host` | **Subsystem only** | **No** RC files | **Yes** |
| `rsync -e ssh …` | Usually `shell -c "rsync --server …"` | **Yes**, same as remote command | **No** if RC exits |
| `ProxyJump` inner leg (`ssh -W %h:%p devbox`) | Minimal; stdio forwarded to `host:22` | Inner session is short-lived | Outer `-N` session unaffected |
| `ControlMaster` master with `-N` | **No** shell on master | **No** | **Yes** |

**Takeaway for tunneling:** use **`-N`** (and put `DynamicForward` in config)
so sshd never invokes your login shell at all. That is the reliable way to keep
a proxy up when someone's dotfiles are broken.

### SCP, SFTP, and subsystems

Both **SCP** and **SFTP** ride on SSH, but they do not all use the same remote
execution path:

- **Legacy SCP** asks sshd to run `scp` as a remote command → goes through
  **`login_shell -c`** → **affected** by broken RC files.
- **Modern SCP** (`scp -s`, default in recent OpenSSH) and **`sftp`** use the
  **`sftp-server` subsystem** built into sshd → **no user shell** → **not
  affected** by `.zshrc`.

If interactive login is broken but `-N` tunnels work, prefer **`sftp`** or
**`scp -s`** to move files until the RC file is fixed.

### Server-side overrides

Even perfect client-side bypass attempts can fail if **sshd** forces a shell:

```sshconfig
# on the server; runs INSTEAD of anything the client asked for
ForceCommand /bin/audit-shell
Match User breakglass
    ForceCommand none
```

`ForceCommand` replaces the client's remote command (and can still invoke your
login shell depending on the forced program). A **`Match`** block for a
**break-glass account** with `ForceCommand none` or a safe wrapper is standard
practice on cloud instances.

### Recovery and prevention

When a bad RC file locks you out:

1. **Use `-N` from your laptop** to bring up forwards without a shell:
   `ssh -N -D 11443 bastion`; often still works.
2. **Use SFTP / `scp -s`** to edit or rename the bad file if you have key auth.
3. **Use a break-glass account** (different user, no broken RC, or
   `ForceCommand /bin/sh` with a minimal environment), keep this outside your
   normal dotfiles workflow.
4. **Use the cloud/provider serial console or recovery mode** when SSH is fully
   dead and you have no alternate account.
5. **Never test RC changes in your only open session**, open a *second* SSH
   window first; keep the first as your lifeline until the new session proves
   healthy.

### Key takeaways

- SSH **always routes remote commands through the login shell** from
  `/etc/passwd`; you cannot "ssh straight to bash" without that shell running
  first.
- **`-N` is different:** no remote shell, no RC files: ideal for `-D`/`-L`/`-R`
  tunnels and the main reason this guide uses it everywhere.
- **SCP (legacy) and `ssh host cmd`** share the same RC-file trap; **SFTP,
  `scp -s`, and `-N` forwards** do not.
- Maintain **alternative access** (break-glass user, console, provider recovery)
  before editing shell startup files on production or cloud hosts.

---

## 12. Closing the Tunnel

### Foreground (`ssh -N bastion`)

It occupies your terminal. Just press **`Ctrl-C`**, or close the terminal
window. Both tear down the SSH connection and free port `11443`.

### Backgrounded (`ssh -fN` or `ssh -N ... &`)

There's no terminal to Ctrl-C, so kill the process:

```bash
# Find it
pgrep -af "ssh -N bastion"         # shows PID + command
ss -ltnp 'sport = :11443'          # ss shows the owning pid
lsof -i :11443                     # alternative

# Kill it
kill <PID>                         # graceful
pkill -f "ssh -N bastion"          # by command pattern
```

### Clean, recommended way: connection multiplexing (`ControlMaster`)

Set up a control socket once, and you get explicit lifecycle commands instead
of hunting for PIDs. Add to `~/.ssh/config`:

```sshconfig
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p     # one Unix socket per connection
    ControlPersist 10m                 # keep master alive 10 min after last use
```

#### What multiplexing actually does

Normally every `ssh host` opens a brand-new TCP connection and runs the full
handshake again: key exchange, host-key check, and **authentication** (password
prompt, key, or MFA). Multiplexing collapses all of that into a single shared
connection:

- The **first** ssh to a host becomes the **master**. It does the real TCP +
  crypto + auth handshake, then opens a **Unix-domain control socket** on your
  laptop at the `ControlPath` location.
- Every **later** `ssh host` (or `scp`, `rsync -e ssh`, `git`, a new tunnel…)
  sees that socket and becomes a **slave**: it tunnels a fresh SSH *channel*
  over the master's existing connection. **No new TCP handshake, no second
  auth prompt, near-instant startup.** This is also why you only get MFA-prompted
  once.

#### The three directives, in detail

- **`ControlMaster`**: how a connection participates:
  - `auto` (recommended): reuse an existing master if one is alive, otherwise
    become the master. This is what makes "first one opens it, rest reuse it"
    automatic.
  - `yes`: always try to *be* the master (fails if a socket already exists).
  - `no`: never multiplex (default if unset).
  - `ask` / `autoask`: like `yes`/`auto` but confirm before reusing.

- **`ControlPath`**: the filesystem path of that control socket. The tokens
  expand per connection so each `user@host:port` gets its own file:
  - `%r` = remote user, `%h` = host, `%p` = port, `%n` = the original name you
    typed, `%C` = a short hash of `%l%h%p%r`.
  - **Watch the length limit.** A Unix socket path must fit in ~104 characters;
    long usernames/hostnames can overflow it and you'll see
    "*ControlPath too long*". Use `ControlPath ~/.ssh/cm-%C` to sidestep this
    with a fixed-length hash.

- **`ControlPersist`**: what happens to the master after the process that
  *started* it exits:
  - `10m` (or `30s`, `1h`…): keep the master in the background that long after
    the **last** client detaches, then auto-close. Great for "tear down a few
    seconds after I'm done."
  - `yes`: keep the master alive **indefinitely** until you `ssh -O exit`.
  - `no`: the master dies the moment its originating client exits (so a
    foreground `ssh` holds it; backgrounding won't persist it).

#### Managing the connection by name

```bash
ssh -fN bastion                    # start tunnel in background (master)
ssh -O check bastion               # is the master alive? prints its PID
ssh -O exit  bastion               # cleanly close the master + ALL its tunnels
ssh -O stop  bastion               # stop accepting new slaves but keep existing ones
```

You can also add/drop forwards on a **live** master without restarting it:

```bash
ssh -O cancel  -D 11443 bastion              # remove the dynamic (SOCKS) forward
ssh -O forward -D 11443 bastion              # add it back later
ssh -O forward -L 8080:wiki.internal:443 bastion   # add a local forward on the fly
ssh -O cancel  -L 8080:wiki.internal:443 bastion   # and remove it
```

`ssh -O exit` is the tidiest shutdown: it terminates the master connection,
which automatically closes every channel and forward riding on it, and releases
the listening socket on `127.0.0.1:11443`.

#### Trade-offs and gotchas

- **All slaves die when the master exits** (`-O exit` or a network drop). If you
  need truly independent sessions, don't share one master for them.
- **Stale sockets.** If the master is killed uncleanly, a dead `ControlPath`
  file can linger and block new connections; delete it (`rm ~/.ssh/cm-*`) or
  rely on `ControlPersist`'s cleanup.
- **Not available on Windows OpenSSH**; it has no Unix-domain control sockets
  (see the Windows notes in [Section 2](#2-how-a-socket-listener-works) and the
  walkthrough in [Section 19](#19-windows-end-to-end-worked-example); manage
  tunnels by PID there instead.

---

## 13. Keepalives, Resilience & Auto-Reconnect

A long-lived tunnel is fragile: NAT gateways and firewalls silently drop idle
TCP connections after a few minutes, laptops sleep, and Wi-Fi changes networks.
When the underlying SSH connection dies, your `127.0.0.1:11443` proxy goes dead
too; often *without* the listener closing, so the browser just hangs. These
directives keep the tunnel healthy or restart it.

### Keepalives: detect a dead connection quickly

```sshconfig
Host *
    ServerAliveInterval 30      # send an encrypted probe every 30s of silence
    ServerAliveCountMax 3       # give up after 3 unanswered probes (~90s)
    TCPKeepAlive yes            # also enable OS-level TCP keepalives
```

- **`ServerAliveInterval` / `ServerAliveCountMax`** are the important pair. The
  ssh **client** sends an *encrypted application-layer* request through the
  connection every `Interval` seconds of inactivity; if `CountMax` of them go
  unanswered, ssh declares the link dead and exits. Because the probe rides
  *inside* the SSH channel, it both (a) keeps NAT/firewall state alive so the
  connection isn't culled, and (b) lets ssh notice a truly dead peer in
  bounded time instead of hanging forever.
- **`TCPKeepAlive`** is the OS-level TCP keepalive (empty ACKs). It's coarser
  (kernel defaults are ~2 hours) and spoofable by middleboxes, so it's a weak
  backstop. The `ServerAlive*` mechanism is what you actually rely on.

### Fail loudly if the forward can't be set up

```sshconfig
Host bastion2
    DynamicForward 127.0.0.1:11443
    ExitOnForwardFailure yes
```

**`ExitOnForwardFailure yes`** makes ssh **abort the whole connection** if the
`-D`/`-L` listener can't bind (e.g. port `11443` is already taken) or a forward
can't be established. Without it, `ssh -fN` can succeed and sit in the
background giving you a perfectly good SSH session with a **broken proxy**, the
worst kind of failure because everything *looks* fine. Always pair it with
backgrounded tunnels.

### Auto-reconnect with `autossh`

`autossh` wraps ssh, watches the tunnel, and respawns it when it dies:

```bash
autossh -M 0 -fN bastion2
```

- **`-M 0`** disables autossh's own legacy monitoring port and tells it to rely
  on the `ServerAlive*` settings above to detect failure; the recommended
  modern setup.
- Everything else (`-fN`, `-J`, `-D`, config host) is passed straight through
  to ssh, so your `~/.ssh/config` still drives the actual connection.

### Run it as a background service

For a tunnel that survives logout and starts at boot, wrap it in a **systemd
user service**:

```ini
# ~/.config/systemd/user/socks-tunnel.service
[Unit]
Description=SOCKS tunnel to bastion2
After=network-online.target

[Service]
ExecStart=/usr/bin/autossh -M 0 -N bastion2
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
systemctl --user enable --now socks-tunnel.service
```

(`Restart=always` makes systemd itself a second safety net on top of autossh.)

---

## 14. Security Model & Trust

Tunneling reroutes your traffic through machines you may not fully control.
Know exactly what each party can and cannot see.

### What the intermediate hops can see

With `ProxyJump` (the `-W` mechanism), encryption is **end-to-end between your
laptop and the final host**. Every intermediate hop (devbox, bastion) relays
only **opaque ciphertext**:

- They **cannot** read your traffic, credentials, or the destinations you visit.
- They **can** see *metadata*: that an SSH connection from you to the next hop
  exists, plus its timing and byte volume.

This is a major reason to prefer `-J`/`ProxyJump` over the old habit of SSHing
into bastion and running another `ssh` from there: the chained-`ssh` approach
terminates a separate session on each hop, so each hop sees plaintext of the
*next* leg's setup.

### What the EXIT host can see

The exit host is the one machine that makes the real outbound TCP connection
and (with remote DNS) resolves your hostnames. It therefore sees:

- **Every destination IP, port, and hostname** you reach through the proxy.
- **The full plaintext of any unencrypted protocol** (plain HTTP, plain
  Redis/SMTP/etc.).

What it **cannot** read is anything wrapped in its own end-to-end encryption:
**HTTPS/TLS payloads stay private** between your browser and the destination, the exit host only relays encrypted bytes (SOCKS sits at the TCP layer, below
TLS, as shown in [Section 10](#10-verifying-the-tunnel-with-curl)). **Bottom
line: you must trust your exit host as much as you'd trust your own machine for
plaintext traffic.**

### Do NOT use agent forwarding (`-A`) to reach deeper hosts

It's tempting to use `ssh -A` so your SSH key "follows" you across hops. **Avoid
it for untrusted hops.** With `-A`, ssh exposes your local agent's socket on the
remote host; anyone with root there can hijack it and authenticate **as you** to
anything your key opens, for as long as you're connected.

`ProxyJump` is the safe alternative: authentication for *every* hop is performed
**from your laptop**, so your private key and agent never touch the
intermediate machines. Ensure your public key (or an SSH CA cert) is authorized
on each hop, and leave `-A` off.

### Other hardening notes

- **Bind to loopback.** `127.0.0.1:11443` keeps the proxy private to your
  machine. Never bind `0.0.0.0` on a shared/multi-user box, and remember that
  *any* local user can reach `127.0.0.1`, so on a shared laptop other users can
  use your tunnel into the private network.
- **Verify host keys.** Each hop's host key is checked against `known_hosts`
  (trust-on-first-use on the first connect). For fleets, prefer an SSH
  certificate authority over scattered `known_hosts` entries.
- **Lock down the exit `sshd`** with `PermitOpen`/`AllowTcpForwarding` if you
  control it, to limit which destinations a forwarded session may reach.

---

## 15. Performance, MTU & sshuttle

### The TCP-over-TCP problem

A SOCKS/`-L`/`-R` tunnel carries your application's **TCP** *inside* the SSH
connection, which is **itself TCP**. Both layers run their own congestion
control and retransmit timers. On a clean link this is fine, but when the
*outer* connection loses packets and retransmits, the *inner* TCP, which can't
see the loss, also fires its own retransmits, and the two stacks fight each
other. Throughput can collapse ("TCP meltdown") on lossy or high-latency
(long-fat) links. Mitigations:

- **Keep chains short.** Each hop adds latency and another serialization point.
- **Use a hardware-accelerated cipher:** `-c aes128-gcm@openssh.com` is usually
  fastest on CPUs with AES-NI; `chacha20-poly1305` wins only without AES-NI.
- **`Compression yes`** helps *only* on slow links with compressible data; on
  fast links it just burns CPU. Leave it off by default.
- For sustained high-bandwidth transfers over long distances, the **HPN-SSH**
  patches enlarge SSH's internal flow-control windows (the stock window is the
  usual bottleneck).

### MTU / MSS

Tunneled packets carry extra headers (SSH framing + an outer TCP/IP header), so
the effective payload size shrinks. For ordinary `-L`/`-D`/`-R` forwarding this
is handled transparently because each leg is its own TCP stream with normal MSS
negotiation; you rarely touch MTU. It *does* matter for `tun`-based VPN-style
tools (including `sshuttle --tproxy` and OpenVPN), where you may need to lower
the tunnel interface MTU to avoid fragmentation, especially if a VPN is also in
the path.

### sshuttle: a "poor man's VPN over SSH"

`sshuttle` gives you VPN-like, transparent access without SOCKS config. Instead
of port forwarding, it captures your outbound TCP (and optionally DNS) with the
local firewall (iptables/nft/pf) and ships it over an ordinary SSH connection to
a small **Python** helper it auto-uploads to the remote host, which makes the
real connections.

```bash
sshuttle -r bastion 10.0.0.0/8 --dns           # route a subnet + DNS via bastion
sshuttle -r bastion -e 'ssh -J devbox' 10.0.0.0/8   # through a jump host
sshuttle -r bastion 0/0                        # route EVERYTHING (full tunnel)
```

**Pros**

- **No per-app config.** Works for *every* TCP app; including statically-linked
  Go binaries that `proxychains` can't hook.
- **Route by subnet**, and forward DNS with `--dns`.
- **Minimal remote requirements:** just Python on the remote; **no root on the
  remote**, no special server software.
- **Chains** through your bastion path via `-e 'ssh -J devbox'`.

**Cons / caveats**

- **TCP-over-TCP meltdown still applies**; it tunnels over SSH/TCP.
- **TCP only** (plus DNS via `--dns`). **No UDP, no ICMP** → no `ping`, and
  QUIC/HTTP3 silently falls back to TCP. A real UDP VPN won't.
- **Needs root *locally*** (`sudo`) to install the firewall rules.
- **Needs Python on the remote host.**
- Per-connection setup latency; not ideal for huge fan-out.

---

## 16. When to Use What (Decision Guide)

There's no single best tool, pick by *what* you need to reach and *how much* of
your traffic should be redirected.

| Approach | Best for | Needs root? | Scope of redirect |
|---|---|---|---|
| `-D` (SOCKS) + `-J` | browsing many internal hosts from SOCKS-aware apps | no | per-app (apps you point at the proxy) |
| `-L` (local forward) | one/few fixed services (a DB, a single web UI) | no | one host:port per forward |
| `-R` (reverse forward) | exposing a *local* service outward, NAT traversal, webhooks | no* | one host:port, reverse direction |
| `sshuttle` | transparent VPN-like access to whole subnets for *all* TCP apps | yes (local) | chosen subnets (TCP + DNS) |
| Full VPN (WireGuard/OpenVPN/corp) | UDP/ICMP/non-TCP, stable whole-network access, org mandate | yes | whatever the VPN routes |

<sub>* `-R` may need `GatewayPorts yes` on the server to expose beyond loopback.</sub>

### The full-tunnel VPN caveat

Many corporate VPNs are configured **full tunnel**: on connect they push a
default route (`0.0.0.0/0`), so **all** your traffic is forced through the VPN,
not just the internal subnets you actually need. Consequences to plan for:

- You may **lose access to your local LAN** (printers, NAS, other devices) and
  general internet can route oddly or slowly through the corporate egress.
- It can **conflict with your SSH tunnels**: once the VPN owns the default
  route, your `ssh` to devbox may itself get pulled through the VPN, or break
  entirely if the VPN policy blocks it.
- **Split-tunnel** VPNs route only specific subnets and leave your
  local/internet traffic alone, preferable when you control the config, but
  many orgs enforce full tunnel for security/DLP reasons.

This is precisely why SSH-based tunneling is attractive for *targeted* access:
`-D`/`-L`/`sshuttle <subnet>` are **inherently split**; you decide exactly what
goes through the tunnel, and everything else uses your normal connection.

---

## 17. IPv6 Notes

Everything in this guide works over IPv6; the only catch is **syntax**, because
IPv6 addresses contain colons that clash with the `host:port` separator.

- **Bracket IPv6 literals** in any forward spec so the port colon is
  unambiguous:

```bash
ssh -L '[::1]:8080:[fd00:abcd::25]:443' devbox -N   # local forward, IPv6 both ends
ssh -D '[::1]:11443' devbox -N                       # SOCKS bound to IPv6 loopback
ssh -R '[::1]:8080:[::1]:3000' bastion -N            # reverse forward
```

- **`localhost` ambiguity (`127.0.0.1` vs `::1`).** If you bind the proxy to
  `127.0.0.1` but an app resolves `localhost` to `::1` first (or vice versa), it
  will fail to connect. Either point the app at the **exact literal** you bound,
  or bind both families. curl: `curl --socks5-hostname '[::1]:11443' https://…`.
- **SOCKS5 carries IPv6 natively** via `ATYP=0x04`, and with `socks5h` the exit
  host resolves **AAAA** records remotely, the clean way to reach IPv6-only
  internal hosts whose names don't resolve on your laptop (see
  [Section 8](#8-dns-and-proxy-dns-socks5-vs-socks5h)).
- **Config files:** `HostName` takes a bare IPv6 address (no brackets); set the
  port with the separate `Port` directive. On the command line, use
  `ssh -p 22 user@2001:db8::1` or bracket forms in connection strings.
- **Force a family** when a host is dual-stack and one path is broken: `ssh -4`
  / `ssh -6`, or `AddressFamily inet` / `inet6` in config.
- **Exposure:** binding to `::` is the IPv6 analogue of `0.0.0.0`; it listens
  on *all* IPv6 interfaces. Same caution as [Section 14](#14-security-model--trust).

---

## 18. Troubleshooting Common Errors

| Symptom / message | Likely cause | Fix |
|---|---|---|
| `bind: Address already in use` (or `cannot listen to port: 11443`) | A previous tunnel still owns the port | `ss -ltnp 'sport = :11443'` to find it, then `kill` / `ssh -O exit`; or pick another port |
| `channel N: open failed: administratively prohibited` | Exit host's `sshd` has `AllowTcpForwarding no` (or `PermitOpen` blocks it) | Enable forwarding on the exit host's `sshd_config`, or use a host that allows it |
| `channel N: open failed: connect failed: Connection refused/timed out` | Exit host reached the destination but nothing is listening / a firewall blocks it | From the exit host, test `nc -vz dest 443` directly; fix the service or firewall |
| Browser shows a **public/wrong IP** or "server not found" for internal names | DNS is being resolved **locally**, not at the exit | Enable remote DNS: Firefox "Proxy DNS", or `socks5h`/`--socks5-hostname` ([Section 8](#8-dns-and-proxy-dns-socks5-vs-socks5h)) |
| `ControlPath too long` | `%r@%h:%p` expands past the ~104-char socket limit | Use `ControlPath ~/.ssh/cm-%C` (hash); see [Section 12](#12-closing-the-tunnel) |
| `mux_client_request_session: read from master failed` / "control socket connect: No such file" | Stale or dead control socket | `rm ~/.ssh/cm-*` and reconnect |
| Tunnel works, then **hangs after a few minutes idle** | NAT/firewall dropped the idle TCP connection | Add `ServerAliveInterval`/keepalives, or `autossh` ([Section 13](#13-keepalives-resilience--auto-reconnect)) |
| `Permission denied (publickey)` on a deeper hop | Your key isn't authorized on that hop | With `ProxyJump`, auth happens laptop→each-hop; authorize your key (or a CA cert) on **every** hop; don't reach for `-A` ([Section 14](#14-security-model--trust)) |
| `-fN` returns instantly but the proxy doesn't work | Forward failed silently in the background | Add `ExitOnForwardFailure yes` so it fails loudly ([Section 13](#13-keepalives-resilience--auto-reconnect)) |
| SSH drops instantly on login; `bash --norc` bypass fails | `exit` or bad command in shell RC (`.zshrc`, `.zshenv`, …) | Use `ssh -N` for tunnels (no shell spawned); fix RC via SFTP/`scp -s`, break-glass account, or console ([Section 11](#11-what-happens-when-you-ssh-shell-execution)) |
| `Bad local forwarding specification` with an IPv6 address | Missing brackets around the IPv6 literal | Bracket it: `-L '[::1]:8080:[fd00::1]:443'` ([Section 17](#17-ipv6-notes)) |
| `nc: invalid option -- 'X'` in a ProxyCommand | Wrong `netcat` variant (GNU vs OpenBSD vs ncat) | Check `man nc` on the relay host; use `ncat --proxy` or `socat` instead ([Section 4](#4-proxycommand--netcat-style-relays)) |

**General technique:** run the tunnel in the foreground with verbose logging to
see exactly which leg fails:

```bash
ssh -vvv -N -D 11443 -J devbox bastion    # -v, -vv, -vvv = more detail
```

Watch for the line naming the hop where the handshake or channel open fails;
that pinpoints whether the problem is connectivity, auth, forwarding policy, or
DNS.

---

## 19. Windows End-to-End Worked Example

A complete walkthrough using the **built-in Windows OpenSSH client** in
PowerShell. The `ssh` commands themselves are identical to Unix; only the
*operational* tooling (backgrounding, finding/killing, no `ControlMaster`)
differs.

### 1. Confirm the OpenSSH client is present

```powershell
ssh -V                          # e.g. OpenSSH_for_Windows_9.5p1
# If missing (older builds):
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### 2. Create the config at `%USERPROFILE%\.ssh\config`

`ControlMaster` is unsupported on Windows, so omit it. Keepalives and
`ProxyJump` work fine:

```sshconfig
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host devbox
    HostName devbox.example.com
    User youruser

Host bastion
    HostName bastion.internal
    User youruser
    ProxyJump devbox

Host bastion2
    HostName bastion2.deep
    User youruser
    ProxyJump bastion
    DynamicForward 127.0.0.1:11443
    ExitOnForwardFailure yes
```

### 3. Set up your key and the agent

```powershell
ssh-keygen -t ed25519                                   # if you don't have a key
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add                                                 # loads ~\.ssh\id_ed25519
```

### 4. Start the tunnel

Windows OpenSSH backgrounding (`-f`) is unreliable, so either run it in its own
window, or detach it with `Start-Process`:

```powershell
# Option A: dedicated window, Ctrl-C to stop
ssh -N bastion2

# Option B: background (hidden) process
Start-Process ssh -ArgumentList '-N','bastion2' -WindowStyle Hidden
```

### 5. Point a browser at the SOCKS proxy

Firefox config is identical to Unix. For Chrome:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  --user-data-dir="$env:TEMP\socks-profile" `
  --proxy-server="socks5://127.0.0.1:11443"
```

### 6. Verify (use `curl.exe`, not the PowerShell alias)

In PowerShell, `curl` is an alias for `Invoke-WebRequest`, which doesn't do
SOCKS, call the real `curl.exe` (shipped with Windows 10+):

```powershell
PS C:\> curl.exe --socks5-hostname 127.0.0.1:11443 https://ifconfig.me
198.51.100.42
```

### 7. Find and close the tunnel (by PID: no `ssh -O exit`)

```powershell
Get-NetTCPConnection -LocalPort 11443 | Select-Object OwningProcess
# or:  netstat -ano | findstr 11443
Stop-Process -Id <pid>          # or:  taskkill /PID <pid> /F
```

### Windows resilience options

There's no native `autossh`. To keep a tunnel up you can:

- Register a **Scheduled Task** that runs `ssh -N bastion2` at logon with
  "restart on failure," or
- Run it inside **WSL**, where the full Linux toolchain (`autossh`, `ss`,
  `ControlMaster`, systemd-style management) is available unchanged.

---

## 20. Complete, Ready-to-Paste ~/.ssh/config

This combines the full four-host chain, the SOCKS proxy, keepalives, and
connection multiplexing for clean shutdowns. Adjust hostnames/users. (Windows
users: drop the three `Control*` lines, see
[Section 19](#19-windows-end-to-end-worked-example).)

```sshconfig
# ── Global defaults: multiplexing + keepalives ──────────────────────
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
    TCPKeepAlive yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

# ── Hop 1: reachable directly from the laptop ───────────────────────
Host devbox
    HostName devbox.example.com
    User youruser

# ── Hop 2: reachable from devbox ────────────────────────────────────
Host bastion
    HostName bastion.internal          # resolved from devbox's view
    User youruser
    ProxyJump devbox

# ── Hop 3 (final): reachable from bastion; SOCKS exits HERE ─────────
Host bastion2
    HostName bastion2.deep             # resolved from bastion's view
    User youruser
    ProxyJump bastion                  # chains through devbox -> bastion
    DynamicForward 127.0.0.1:11443     # SOCKS5 proxy on the laptop
    ExitOnForwardFailure yes           # fail loudly if 11443 can't bind
```

Usage:

```bash
# Bring up the proxy (background); SOCKS exits at bastion2
ssh -fN bastion2

# Verify it
curl --socks5-hostname 127.0.0.1:11443 https://ifconfig.me

# Tear it down cleanly
ssh -O exit bastion2
```

> If you have only three hosts (laptop → devbox → bastion), delete the
> `bastion2` block and move the `DynamicForward 127.0.0.1:11443` /
> `ExitOnForwardFailure yes` lines into the `bastion` block.

> **Note:** there is no config directive for `-N`. To bring up a tunnel without
> a shell, use `ssh -N` (or `ssh -fN` for background) on the command line.

---

## 21. Quick Reference / Cheat Sheet (per OS)

### Tunnel commands: identical on Linux, macOS, and Windows OpenSSH

The `ssh`/`curl` commands themselves are cross-platform. (On Windows, call
`curl.exe` so you don't hit the PowerShell `Invoke-WebRequest` alias.)

| Task | Command |
|---|---|
| SOCKS via one jump | `ssh -D 11443 -J devbox bastion -N` |
| SOCKS via chain | `ssh -D 11443 -J devbox,bastion bastion2 -N` |
| Local forward (static) | `ssh -L 8080:wiki.internal:443 devbox -N` |
| Reverse forward | `ssh -R 8080:localhost:3000 bastion -N` |
| Nested SOCKS (devbox step) | `ssh -D 1080 bastion -N`  *(run on devbox)* |
| Nested SOCKS (laptop step) | `ssh -L 11443:127.0.0.1:1080 devbox -N` |
| ssh *through* a SOCKS proxy | `ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:11443 %h %p' deep-host` |
| IPv6 SOCKS bind | `ssh -D '[::1]:11443' devbox -N` |
| From config | `ssh -N bastion2` |
| Verify exit + DNS | `curl --socks5-hostname 127.0.0.1:11443 https://ifconfig.me` |

### SSH flags used in this guide

| Flag | Meaning |
|---|---|
| `-D [bind:]port` | dynamic forward → local **SOCKS** proxy |
| `-L [bind:]lport:dhost:dport` | local forward → fixed remote destination |
| `-R [bind:]rport:dhost:dport` | reverse forward → listener on the server side |
| `-J host[,host…]` | ProxyJump: reach the target *through* jump host(s) |
| `-W host:port` | forward stdio to host:port on the next hop (what `-J` uses) |
| `-N` | no remote command, **no login shell**; holds forwards only |
| `-t` | force pseudo-TTY (needed for some interactive commands; still runs through login shell) |
| `-T` | disable TTY allocation (opposite of `-t`; RC rules unchanged) |
| `-f` | go to background after auth (Unix; unreliable on Windows) |
| `-O cmd` | control a multiplexed master (`check`/`exit`/`stop`/`forward`/`cancel`) |
| `-v`/`-vv`/`-vvv` | increasing debug verbosity |

### Operational tooling: differs by OS

"Unix" = Linux **and** macOS (the `ssh` side is identical; only these inspection
commands differ, and between Linux/macOS only `ss` vs `lsof`).

| Task | Unix (Linux / macOS) | Windows (PowerShell) |
|---|---|---|
| Background the tunnel | `ssh -fN bastion2` | `Start-Process ssh -ArgumentList '-N','bastion2' -WindowStyle Hidden` |
| Find listener by port | Linux: `ss -ltnp 'sport = :11443'`<br>macOS: `lsof -i :11443` | `netstat -ano \| findstr 11443`<br>or `Get-NetTCPConnection -LocalPort 11443` |
| Find the ssh process | `pgrep -af "ssh -N"` | `Get-Process ssh` |
| Kill it | `kill <pid>`  /  `pkill -f "ssh -N"` | `Stop-Process -Id <pid>`  /  `taskkill /PID <pid> /F` |
| Multiplex check / close | `ssh -O check bastion2` / `ssh -O exit bastion2` | *n/a, `ControlMaster` unsupported; kill by PID* |
| Auto-reconnect | `autossh -M 0 -fN bastion2` | Scheduled Task, or run it under WSL |
| Config file path | `~/.ssh/config` | `%USERPROFILE%\.ssh\config` |

**Mental recap**

- **Listener** = a local socket (`bind` + `listen` + `accept`) where ssh plays
  SOCKS server; each app connection becomes a multiplexed SSH **channel** that
  exits at the far end.
- **More hops** = extend `ProxyJump` (`-J a,b,c` or chained config); SOCKS exits
  at the last host.
- **`-L` vs `-R`** = `-L` listens on your laptop and reaches *in*; `-R` listens
  on the server and reaches *back* to you.
- **Proxy DNS** = send the hostname (not IP) so the **exit host** resolves it;   essential for internal / split-horizon names.
- **`--socks5-hostname`** proves the chain: remote DNS + the returned IP = the
  exit host's egress IP, with TLS staying end-to-end private.
- **Closing** = Ctrl-C in foreground; for background use `ControlMaster` +
  `ssh -O exit` (or just `kill` the pid).
- **Resilience** = `ServerAliveInterval`/`CountMax` to detect death,
  `ExitOnForwardFailure yes` to fail loud, `autossh -M 0` to auto-reconnect.
- **Trust** = intermediate hops see only ciphertext; the **exit host** sees all
  destinations + any plaintext. Never agent-forward (`-A`) to untrusted hops,   `ProxyJump` keeps your key on the laptop.
- **Shell / `-N`** = remote commands go through your **login shell** and its RC
  files; `-N` skips the shell entirely, use it for tunnels when dotfiles are broken.

---

## 22. Glossary

| Acronym | Stands for | What it is / does here |
|---|---|---|
| SSH | Secure Shell | Encrypted protocol for remote login and tunneling; the foundation of everything in this guide |
| SOCKS | SOCKetS (Secure) | A proxy protocol that relays arbitrary TCP; `ssh -D` makes ssh a SOCKS5 server |
| SOCKS5h | SOCKS5 with **h**ostname resolution | Variant where the **proxy/exit** resolves DNS (not the client), fixes internal/split-horizon names |
| ATYP | Address TYPe | SOCKS5 field selecting IPv4 (`0x01`), domain name (`0x03`), or IPv6 (`0x04`) for the target |
| DNS | Domain Name System | Resolves names (`wiki.internal`) to IPs; "remote DNS" means the exit host does it |
| TCP | Transmission Control Protocol | Reliable, ordered byte streams; what SSH forwards (and runs on) |
| UDP | User Datagram Protocol | Connectionless datagrams; **not** carried by SSH forwards or `sshuttle` |
| ICMP | Internet Control Message Protocol | Control/diagnostic packets (e.g. `ping`); not tunnelable via SSH forwards |
| IP | Internet Protocol | The addressing/routing layer; addresses come in IPv4 and IPv6 |
| NAT | Network Address Translation | Router rewriting of addresses; its idle timeouts are why tunnels need keepalives |
| MTU | Maximum Transmission Unit | Largest packet a link carries; tunneling overhead shrinks the usable size |
| MSS | Maximum Segment Size | TCP's per-segment payload limit, derived from MTU; auto-negotiated per stream |
| PMTUD | Path MTU Discovery | Mechanism to learn the smallest MTU on a path; can misbehave through tunnels/VPNs |
| TLS | Transport Layer Security | End-to-end encryption (HTTPS) *inside* the tunnel; even the exit host can't read it |
| CA | Certificate Authority | Issues signing certs; an SSH CA can replace scattered `known_hosts`/`authorized_keys` |
| MFA | Multi-Factor Authentication | Extra login factor; `ControlMaster` lets you satisfy it once per master connection |
| TOFU | Trust On First Use | Accepting a host key the first time you connect, then pinning it in `known_hosts` |
| LAN | Local Area Network | Your local network; binding `0.0.0.0` would expose the proxy to it |
| VPN | Virtual Private Network | Network-layer tunnel; "full tunnel" routes *all* traffic and can break local/SSH access |
| fd | File Descriptor | Integer handle the OS gives for a socket/file on Unix ("everything is a file") |
| PID | Process IDentifier | Number used to find/kill a backgrounded `ssh` tunnel |
| IOCP | I/O Completion Ports | Windows' high-performance async I/O model (Winsock), in place of `epoll`/`kqueue` |
| HPN | High Performance Networking | SSH patch set that enlarges flow-control windows for long-fat links |
| CLI | Command-Line Interface | Terminal tools (vs GUI); many lack SOCKS settings, hence `proxychains`/`ALL_PROXY` |
| RC | Run Commands | Shell startup files (`.zshrc`, `.bashrc`, `.zshenv`, …) executed when a shell starts |
| sshd | SSH daemon | Server-side SSH program; reads `/etc/passwd`, spawns login shell or subsystems |
