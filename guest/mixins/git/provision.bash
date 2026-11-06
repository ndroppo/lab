#!/bin/bash
# Lab mixin: shared-project Git. Runs as root after base on every boot.

agent=$PARAM_LabAgentUser

# The same locked .git pointer names the host's store there and an
# agent-owned metadata copy here. Prepare only the guest-local root, never
# its contents. Its parents must stay outside mounts and beyond the agent's
# ability to replace them with symlinks before the next root boot script.
store=$PARAM_LabGitOrigin
if [[ $store != /* || $store == / || $(realpath -m "$store") != "$store" ]]; then
  echo "git mixin: LabGitOrigin must name a physical absolute directory path." >&2
  exit 1
fi
parent=${store%/*}
parent=${parent:-/}
while :; do
  if [[ -e $parent ]]; then
    if [[ ! -d $parent ]] || runuser -u "$agent" -- test -w "$parent"; then
      echo "git mixin: unsafe guest git-store parent $parent; it must be a directory the agent cannot replace entries in." >&2
      exit 1
    fi
    if [[ $(findmnt -T "$parent" -n -o FSTYPE) == virtiofs ]]; then
      echo "git mixin: the guest git store cannot sit inside a host mount: $parent" >&2
      exit 1
    fi
  fi
  [[ $parent == / ]] && break
  parent=${parent%/*}
  parent=${parent:-/}
done
if [[ -e $store ]]; then
  [[ -d $store && ! -L $store && $(stat -c %U "$store") == "$agent" && $(findmnt -T "$store" -n -o FSTYPE) != virtiofs ]] || {
    echo "git mixin: $store is not the agent's guest-local git directory." >&2
    exit 1
  }
else
  parent=${store%/*}
  mkdir -p "${parent:-/}" && install -d -o "$agent" -g "$agent" -m 700 "$store" || exit 1
fi
install -d -o "$agent" -g "$agent" -m 700 /run/lab-git || exit 1
/usr/bin/git config --system user.name "$agent" || exit 1
/usr/bin/git config --system user.email "$agent@localhost" || exit 1

install -d -m 755 /usr/local/bin || exit 1
ln -sfn /lab/mixins/git/git /usr/local/bin/git || exit 1
printf 'LAB_GIT_STORE=%q\n' "$store" >> /etc/lab.env
