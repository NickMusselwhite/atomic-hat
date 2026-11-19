#!/usr/bin/env bash
set -euo pipefail

# Diagnostic only: do not delete package or service state.
# Use the final image, not the NVIDIA builder, because the full application
# set (including libvirt and iSCSI) determines the runtime /var structure.
echo 'Runtime /var/lib directory audit (up to three levels):'
printf '%-7s %-27s %-52s %s\n' 'Entries' 'RPM owner' 'Directory' 'Permissions'
count=0
while IFS= read -r dir; do
    # Check immediate content, not recursive size. Empty directories are often
    # safe candidates for boot-time tmpfiles recreation; nonempty ones require
    # further review and must not be removed indiscriminately.
    if [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        entries=empty
    else
        entries=nonempty
    fi
    if owner="$(rpm -qf --qf '%{NAME}' "$dir" 2>/dev/null)"; then
        :
    else
        owner=unowned
    fi
    perms="$(stat -c '%a %U:%G' "$dir")"
    printf '%-7s %-27s %-52s %s\n' "$entries" "$owner" "$dir" "$perms"
    count=$((count + 1))
done < <(find /var/lib -mindepth 1 -maxdepth 3 -type d -print | sort)
echo "AUDIT: $count directories inspected; no files modified"
