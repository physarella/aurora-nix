# vim: set ft=make :
#
# Imported automatically by /usr/share/ublue-os/justfile via
#   import? "/usr/share/ublue-os/just/60-custom.just"
# so no patching of the main justfile is needed.

CLEAN_HOME_CONF := "/usr/share/ublue-os/clean-home.conf"

# Show what `ujust clean-home` would delete, without deleting anything
clean-home-preview:
    #!/usr/bin/bash
    set -uo pipefail
    echo "== trash + caches older than 30 days =="
    # systemd-tmpfiles logs "Would remove ..." to stderr, not stdout, so 2>&1
    # is required here -- redirecting stderr to /dev/null silently yields zero
    # results and makes the preview look like there is nothing to clean.
    out=$(systemd-tmpfiles --user --clean --dry-run "{{ CLEAN_HOME_CONF }}" 2>&1 \
          | sed -n 's/^Would remove "\(.*\)"$/\1/p')
    n=$(printf '%s' "$out" | grep -c . || true)
    printf '%s\n' "$out" | head -25 | sed 's/^/  /'
    [ "$n" -gt 25 ] && echo "  ... and $((n - 25)) more"
    echo "  $n paths total"
    echo
    echo "== nix store =="
    if command -v nix >/dev/null 2>&1; then
        nix store gc --dry-run 2>&1 | tail -3 | sed 's/^/  /'
    else
        echo "  nix not installed"
    fi

# Delete trash and caches older than 30 days, then collect nix store garbage
clean-home:
    #!/usr/bin/bash
    set -uo pipefail
    before=$(df -B1 --output=avail /var/home | tail -1 | tr -d ' ')

    echo ":: trash + caches older than 30 days"
    systemd-tmpfiles --user --clean "{{ CLEAN_HOME_CONF }}"

    if command -v nix >/dev/null 2>&1; then
        echo ":: nix store"
        # Old profile generations pin their whole closure, so they have to go
        # first or gc has nothing it is allowed to collect.
        nix profile wipe-history --older-than 30d || true
        nix store gc || true
    fi

    after=$(df -B1 --output=avail /var/home | tail -1 | tr -d ' ')
    freed=$((after - before))
    if [ "$freed" -gt 0 ]; then
        echo ":: freed $(numfmt --to=iec "$freed") on /var/home"
    else
        echo ":: nothing to reclaim"
    fi

# Report every top-level entry in $HOME by size and last interaction date
home-report:
    #!/usr/bin/bash
    set -uo pipefail
    cd "$HOME" || exit 1
    echo "scanning $HOME ..." >&2
    find . -xdev -mindepth 1 -printf '%T@\t%s\t%P\n' 2>/dev/null | awk -F'\t' '
    {
      split($3, a, "/"); top = a[1]
      if (top == "") next
      if ($1 > mt[top]) mt[top] = $1
      sz[top] += $2; n[top]++
    }
    END { for (t in mt) printf "%d\t%d\t%d\t%s\n", mt[t], sz[t], n[t], t }
    ' | sort -n | awk -F'\t' '{
      s = $2
      h = (s >= 1073741824) ? sprintf("%.1fG", s/1073741824) \
        : (s >= 1048576)    ? sprintf("%.0fM", s/1048576) \
        :                     sprintf("%.0fK", s/1024)
      printf "%-26s %9s  %8d files  %s\n", $4, h, $3, strftime("%Y-%m-%d", $1)
    }'
