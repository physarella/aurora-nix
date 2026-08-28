# Tooling reference

Preserved from the upstream `ublue-os/image-template` README, trimmed to what
still applies here. Nothing in this file is needed for day-to-day use — the
GitHub Actions workflow builds and signs the image on every push to `main`.
This is for local builds, ISOs, and VM testing.

## Requirements

`just`, `podman` and `jq` are preinstalled on Universal Blue images. Linting
additionally wants `shfmt` and `shellcheck` — both available from nix
(`nix shell nixpkgs#shfmt nixpkgs#shellcheck`) rather than layering them.

## Environment variables

All sourced from `bazzite-nix.env` (referenced by `set dotenv-filename` on line
1 of the `Justfile`, so the two must be renamed together):

| variable | value |
| --- | --- |
| `IMAGE_NAME` | `bazzite-nix` |
| `REPO_ORGANIZATION` | `physarella` |
| `DEFAULT_TAG` | `latest` |
| `BIB_IMAGE` | `quay.io/centos-bootc/bootc-image-builder:latest` |

`build.yml` lowercases `IMAGE_REGISTRY` and `IMAGE_NAME` before pushing, since
ghcr.io paths must be lowercase. `IMAGE_REGISTRY` itself is derived from
`github.repository_owner` and is marked do-not-edit in the workflow.

## Building locally

```bash
just build                      # build the image
just build $target_image $tag   # both args optional
```

Beware: building from a checkout on the WorkVault NTFS mount copies every file
into the image as mode 777. Build from a copy on the internal drive, or let CI
do it — GitHub Actions clones fresh with correct modes.

### Rechunking

Flattens layers so no single layer is enormous. Does not speed up downloads,
but makes them resumable.

```bash
just ostree-rechunk    # via rpm-ostree
just rechunk           # via chunkah
```

### Testing a local build

The image must be in root's containers-storage to rebase onto it. `sudo just
build` and `sudo just ostree-rechunk` build directly as root and skip the
transfer.

```bash
sudo podman image list --filter=label=containers.bootc=1
sudo bootc switch --transport containers-storage localhost/bazzite-nix:latest
```

Then reboot.

## Disk images and VMs

Types are `qcow2`, `iso`, and `raw` — substitute for `qcow2` below.

```bash
just build-qcow2      # build
just rebuild-qcow2    # rebuild
just run-vm-qcow2     # boot it
just spawn-vm rebuild="0" type="qcow2" ram="6G"   # via systemd-vmspawn
```

### ISO builds in CI

`.github/workflows/build-disk.yml` uses
[bootc-image-builder](https://osbuild.org/docs/bootc/). To use it:

1. Point `disk_config/iso-kde.toml` (or `iso-gnome.toml`) at
   `ghcr.io/physarella/bazzite-nix`.
2. Check `IMAGE_REGISTRY`, `IMAGE_NAME` and `DEFAULT_TAG` in `build-disk.yml`
   match this repo.
3. Optionally add S3 secrets to upload the result — `S3_PROVIDER`,
   `S3_BUCKET_NAME`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_REGION`,
   `S3_ENDPOINT`. Without them the images are still downloadable as workflow
   artifacts.

## File management

```bash
just check    # syntax-check the Justfile and all .just files
just fix      # autofix the above
just lint     # shellcheck the shell scripts
just format   # shfmt the shell scripts
just clean    # remove build artifacts
```

## Adding things to the image

Packages, COPRs and unit enablement all go in `build_files/build.sh`:

```bash
dnf5 install -y <package>

dnf5 -y copr enable ublue-os/staging
dnf5 -y install <package>
dnf5 -y copr disable ublue-os/staging   # or it stays enabled on the final image

systemctl enable <unit>
```

Anything under `system_files/` is copied to `/` by the first line of
`build.sh`, so `system_files/usr/lib/systemd/system/foo.service` lands at
`/usr/lib/systemd/system/foo.service`.

Reach for this only for things that genuinely need to be system-level — udev
rules, polkit actions, dbus system services, kernel modules. Ordinary CLI tools
belong in nix, where they install without a rebuild or a reboot.

## Driver support

For additional kernel drivers (Nvidia, OpenRazer, Framework), ublue maintains
[ublue-os/akmods](https://github.com/ublue-os/akmods) with images and scripts
for integrating them into a custom image.

## Artifacthub

The upstream template shipped an `artifacthub-repo.yml` for indexing the image
on [artifacthub.io](https://artifacthub.io). It was removed as unused — it only
contained placeholder credentials. If you ever want to list the image publicly,
re-add it with a real `repositoryID`.
