<img width="1983" height="793" alt="ChatGPT Image May 20, 2026, 02_44_36 PM" src="https://github.com/user-attachments/assets/dfcc6de3-dac5-4f66-910a-e3d5ef22f3d9" />

> *"Delivering crisp produce since 1973."* — Lapin Logistics

A deliberately vulnerable single-box Linux lab for OSCP-style enumeration and exploitation practice. Built around a fictional carrot-delivery startup that hired its rabbits straight out of bootcamp and never looked back.

## What's inside

A realistic mixed-services Linux box with a wide attack surface and plenty of room to practice the fundamentals:

- **A dozen-ish open ports** — TCP and UDP, common and uncommon — to sharpen your enumeration
- **Multiple foothold paths** that reward thorough recon (more than one way in)
- **Several lateral movement and privilege escalation primitives** drawn from real-world misconfigurations
- **Six users** with varying degrees of opsec hygiene (mostly poor)
- **Three flags** scattered across privilege tiers
- A healthy dose of rabbit holes, decoys, and red herrings to keep you honest

No exotic exploits, no kernel CVEs, no guessing games. Everything is reachable from standard tooling and a careful reading of what's actually in front of you.

## Setup

1. Spin up a fresh **Ubuntu VM** (disposable — see warning below). Debian-family should also work. Make sure SSH server is installed during the setup.
2. Clone this repo onto the VM:
```bash
   git clone https://github.com/jacob-aphotic/thewarrenlab.git
   cd thewarrenlab
```
3. Run the installer as root:
```bash
   sudo ./install.sh
```
4. **If the install errors out, just run it again.** Known bug, on the list to fix. Subsequent runs usually finish clean.
5. (Optional) Verify the build:
```bash
   sudo ./install.sh --verify
```
6. Grab the target IP from the banner and go hunt from your attacker box (Kali or whatever you like). Make sure the network config is setup properly (eg. bridged adaptors) so the machine is reachable from your Kali box.

Teardown:
```bash
sudo ./uninstall.sh
```
(Best-effort. VM snapshot rollback is more reliable.)

⚠️ **Disposable VM only.** The installer intentionally disables AppArmor/SELinux, opens the firewall, weakens services, and creates users with terrible passwords. Do not run this on anything you care about. Do not expose the VM to the public internet.

## Difficulty

**Not too bad — but full of rabbit holes.** 🕳️🐇

There are several legitimate paths to a foothold and the privesc chain is recoverable from any of them, but there's also a *lot* of noise: services that look exploitable but aren't, decoy ports, false-positive fingerprints, and at least one thing designed purely to waste your nmap output. Part of the lesson is learning what to ignore.

Bring patience. Take notes. Don't fall down every hole you find.

## Flags

Three flags hidden across the box, each representing a meaningful milestone in the chain, with a flag submission portal on TCP port 1337 so you can pat yourself on the back.

---

*The Warren is open. Happy hunting.* 🥕
