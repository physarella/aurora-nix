# aurora-nix

A custom [Bazzite](https://bazzite.gg) image with [Nix](https://nixos.org) as
the package manager, built on `ghcr.io/ublue-os/aurora:stable`.

The point: install things without a container, without a rebuild, and without
a reboot. Homebrew is gone, distrobox stays for when you genuinely want a
container, and the system layer holds only what actually needs to be there.

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/physarella/aurora-nix:latest
```

## What this changes

**Nix, installed properly.** Fedora 44 packages Nix natively, so it comes from
`dnf5` — binaries in `/usr`, versioned with the image, no `curl | sh` installer
to re-run after every rebase. The store lives on `/var` and is bind-mounted over
the read-only `/nix`. See [docs/nix-integration.md](docs/nix-integration.md) for
how, and for the systemd ordering trap that makes it work.

```bash
nix profile install nixpkgs#ripgrep    # permanent, user-level
nix shell nixpkgs#ffmpeg               # throwaway
nix run home-manager/master -- init --switch
```

**No Homebrew.** The units are masked and the 126 MB `homebrew.tar.zst` is
dropped from the image.

**Only real system packages layered.** `corectrl` (dbus system services and a
polkit helper) and `goxlr-utility` (udev rules, pinned to an upstream GitHub
RPM by sha256). Everything previously layered with `rpm-ostree` is either
included here or deliberately dropped — `build.sh` records which and why.

**`ujust clean-home`.** Trash and caches older than 30 days, plus nix store GC.
Manual by design: the rules live outside every `systemd-tmpfiles` search path,
because the user instance of `systemd-tmpfiles-clean.timer` is enabled by
default and would otherwise run them daily.

```bash
ujust clean-home-preview   # dry run, deletes nothing
ujust clean-home
ujust home-report          # every top-level entry in $HOME by size and last use
```

Not to be confused with Bazzite's own `ujust clean-system`, which runs
`podman image prune -af` and will delete every container image not currently
backing a container — including distrobox base images.

## Layout

| path | what |
| --- | --- |
| `Containerfile` | entrypoint; sets the base image |
| `build_files/build.sh` | all package installs and system changes |
| `system_files/` | copied verbatim to `/` |
| `aurora-nix.env` | image name, org, tag |
| `cosign.pub` | signature verification key |
| `docs/nix-integration.md` | how nix is wired in, and why |
| `docs/tooling.md` | local builds, ISOs, VMs, `just` recipes |

## Signing

The image is signed in CI. `cosign.pub` is the verification half; the private
half is a repository secret named `SIGNING_SECRET`.

Its passphrase must be **empty** — `build.yml` sets `COSIGN_PRIVATE_KEY` but
never sets `COSIGN_PASSWORD`, so a protected key fails the signing step.
`.gitignore` excludes `cosign.key` so the private half cannot be committed.

To regenerate:

```bash
cosign generate-key-pair          # press enter at the passphrase prompt
```

## Upstream

Started from [ublue-os/image-template](https://github.com/ublue-os/image-template),
which remains configured as the `upstream` remote. To pull in template changes:

```bash
git fetch upstream && git merge upstream/main
```
