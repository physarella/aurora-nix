# Nix on Bazzite (no distrobox, no brew)

Fedora 44 packages Nix natively (`nix` 2.34.8), so this image installs it with
`dnf5` like any other package. No `curl | sh`, no Determinate installer, no
third-party repo. The binaries live in `/usr`, versioned with the image and
replaced on every update, which is exactly the bootc model.

## What was added

| File | Purpose |
| --- | --- |
| `build_files/build.sh` | `dnf5 install -y nix`, adds `@wheel` to `trusted-users`, enables the two units |
| `system_files/usr/lib/systemd/system/nix.mount` | bind-mounts `/var/lib/nix` over the read-only `/nix` |
| `system_files/usr/lib/tmpfiles.d/nix-store.conf` | creates the `/var/lib/nix` backing tree |

### Why the bind mount

The `nix-system` RPM creates `/nix/store` and `/nix/var` as real directories, but
on a bootc system that tree lands on the read-only composefs root, and Nix needs
a writable store. So the real store lives on `/var` (persistent, per-machine,
not part of the image) and is bind-mounted over `/nix` at boot.

Fedora's own units are already written for this: `nix-daemon.service` and
`nix-daemon.socket` both carry `RequiresMountsFor=/nix/store`, so systemd orders
them after `nix.mount` automatically, and their
`ConditionPathIsReadWrite=/nix/var/nix/daemon-socket` means they simply do not
start if the store never became writable. Nothing extra to wire up.

A symlink (`/nix -> /var/lib/nix`) would be the more ostree-native idiom, but
Nix ships `allow-symlinked-store = false` by default and flipping it is a real
behavioural deviation. The bind mount keeps `/nix/store` a literal path.

### The ordering trap

`nix.mount` sets `DefaultDependencies=no`, and that is load-bearing. systemd
gives every local mount unit an implicit `Before=local-fs.target`, while
`systemd-tmpfiles-setup.service` — which creates `/var/lib/nix` — is
`After=local-fs.target`. Ordering the mount after tmpfiles with default
dependencies in place closes a cycle, and systemd breaks it by silently
dropping the mount job: no journal entry for `nix.mount` at all, and
`nix-daemon` stays inactive because its condition never passes. Disabling
default dependencies removes the implicit `Before=local-fs.target` and lets the
mount run late, which is fine — nothing in early boot touches `/nix`. The
shutdown ordering that `DefaultDependencies=no` drops is re-added by hand.

If you ever see `nix.mount` "enabled but never ran, no logs", this is why.

## Verified

Built on `fedora-bootc:44` and booted under systemd:

- `bootc container lint` passes; a top-level `/nix` draws no complaint
- `nix.mount` active, `/nix` bind-mounted from `/var/lib/nix`
- `nix-daemon.socket` active
- unprivileged user in `wheel` reports `Trusted: 1`
- `nix profile install nixpkgs#hello` substitutes from cache.nixos.org and runs
- `nix run home-manager/master -- init --switch` completes and activates

## Build and switch

Do not build this on the WorkVault checkout — it is still NTFS-via-FUSE, every
file reads as mode 777, and those modes get copied straight into the image.
Either build from a copy on the internal drive, or let the GitHub Actions
workflow already in this repo do it (it clones fresh with correct modes, and
avoids eating the ~115 GB left on the nvme).

```bash
just build            # local build
bootc switch --enforce-container-sigpolicy ghcr.io/qeu-b-458/bazzite-nix:latest
```

Signing is already wired: `cosign.pub` at the repo root is the verification key,
and its private half has an **empty passphrase**, which matters because
`build.yml` sets `COSIGN_PRIVATE_KEY` but never sets `COSIGN_PASSWORD`. A
passphrase-protected key would fail the signing step. Add the contents of
`~/cosign.key` as a repository secret named `SIGNING_SECRET`; `.gitignore`
already excludes that file so it cannot be committed by accident.

## Using it

```bash
nix profile install nixpkgs#ripgrep     # permanent, user-level, no reboot
nix shell nixpkgs#ffmpeg                # throwaway shell
nix profile list / nix profile remove
```

### home-manager

Standalone home-manager works fine off NixOS — it is just a flake, and it does
not need to be in the image because it lives entirely in the user profile:

```bash
nix run home-manager/master -- init --switch
$EDITOR ~/.config/home-manager/home.nix
home-manager switch
```

Sensible split: the image owns the system (kernel, drivers, system services,
layered RPMs), home-manager owns the user environment (CLI tools, dotfiles,
shell config). Neither needs distrobox.

## Gotchas

- **Disk.** The store is on `/var`, i.e. the nvme, which is already ~88% full.
  `nix store gc` reclaims; `nix profile wipe-history` first, or GC keeps
  everything still referenced by an old generation.
- **`/var` is not in the image.** The store survives image updates and rollbacks
  untouched — that is the point — but it is also not reproducible from the
  image. Back up `~/.config/home-manager`, not `/nix`.
- **Don't put the store on WorkVault.** If the drive is not mounted at boot the
  bind mount fails and every nix-installed binary vanishes from PATH.

## Next step worth doing

The packages currently layered on the host with `rpm-ostree` — `goxlr-utility`
(local RPM), `corectrl`, `boost`, `librealsense`, `libuvc`, `onnxruntime`,
`opencv`, `opencv-video`, `openhmd`, `openvr-api` — are precisely what a custom
image is for. Moving them into `build.sh` gets rid of the layering entirely and
makes the goxlr RPM survive rebases instead of needing to be re-applied.
