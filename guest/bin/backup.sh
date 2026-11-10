#!/bin/bash
# Guest-side, agent-owned backup coordinator. Each selected mixin owns its data.

die() { echo "backup.sh: $*" >&2; exit 1; }
action=backup
case $#:$1 in
  0:) ;;
  1:--restore) action=restore ;;
  *) die "Usage: backup.sh [--restore]" ;;
esac
. /etc/lab.env || die "This is not a provisioned Lab room."
[[ $(id -un) == "$LAB_AGENT" && $EUID != 0 ]] || die "Run as the guest agent, not root."
findmnt -M /mnt/lab-state > /dev/null || die "No state mount. Save this older room's guest-only data before rebuilding."
umask 077
BACKUP=/mnt/lab-state/backup
mkdir -p "$BACKUP" "$HOME/.lab" || exit 1
exec 9> "$HOME/.lab/backup.lock" || exit 1
flock -n 9 || die "Another backup or restore is running."

for name in $LAB_MIXINS; do
  hook=/lab/mixins/$name/backup.bash
  [[ -f $hook ]] || continue
  ( . "$hook" && "$action" ) || exit 1
done
echo "${action^} complete: $BACKUP"
