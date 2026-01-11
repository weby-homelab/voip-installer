# 1. Use Docker Host Networking Mode

Date: 2026-01-10

## Status

Accepted

## Context

VoIP traffic consists of two distinct parts:
1. **SIP Signaling (TCP/TLS):** Uses a single port (5061). Easy to NAT.
2. **RTP Media (UDP):** Uses a large range of dynamic ports (typically 10000-20000).

Running VoIP containers in Docker's default `bridge` mode introduces Double NAT:
1. Provider NAT (Public IP -> Server IP)
2. Docker NAT (Server IP -> Container IP)

SIP protocols embed IP addresses in their payloads (SDP headers). Double NAT breaks audio (one-way audio issues) unless complex ALG (Application Layer Gateway) or ICE/STUN/TURN configurations are perfectly tuned. Furthermore, the `docker-proxy` process consumes significant CPU when managing thousands of UDP port forwards.

## Decision

We will use `network_mode: host` for the Asterisk container.

## Consequences

**Positive:**
* **Performance:** Zero NAT overhead for RTP packets.
* **Simplicity:** No need to map 10,000 ports in Docker Compose (`-p 10000-20000:10000-20000/udp` is resource-intensive).
* **Reliability:** Eliminates one layer of NAT, significantly reducing "one-way audio" issues.

**Negative:**
* **Port Conflicts:** The container shares the host's network namespace. We cannot run another service on port 5061 or 80 on the same host without conflicts.
* **Security Isolation:** Reduced network isolation compared to bridge mode.

**Mitigation:**
We use **NFTables** on the host to strictly filter traffic destined for the container, ensuring that despite sharing the host network, the attack surface remains minimal.
