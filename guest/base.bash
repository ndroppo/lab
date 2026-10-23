#!/bin/bash
# Lab base provisioning: the walls. Runs as root on every boot, before any
# mixin. Idempotent - packages and rules are asserted, not just installed
# once, since a boot is when the walls get re-checked.

if [[ -z $PARAM_LabAgentUser ]]; then
  echo "base: PARAM_LabAgentUser is not set. lab passes it as a Lima param; this instance was not created by lab." >&2
  exit 1
fi
agent=$PARAM_LabAgentUser

# Without this, every sudo call warns that it cannot resolve the host.
grep -qw "$(hostname)" /etc/hosts || echo "127.0.1.1 $(hostname)" >> /etc/hosts

cat > /etc/sysctl.d/99-lab-no-ipv6.conf <<'SYSCTL'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
SYSCTL
sysctl --quiet --system

systemctl disable --now systemd-resolved
# A fresh image ships resolv.conf as a symlink into /run, which is wiped on
# every boot. Replace the link with a real file so the servers survive.
if [[ -L /etc/resolv.conf ]]; then rm /etc/resolv.conf; else chattr -i /etc/resolv.conf; fi
cat > /etc/resolv.conf <<'RESOLV'
nameserver 9.9.9.9
nameserver 149.112.112.112
RESOLV
chattr +i /etc/resolv.conf

# --badname: Debian-family useradd rejects the dot otherwise. On repeat
# boots both commands say "already done" in their own words; that's fine.
useradd --badname -m -s /bin/bash "$agent"
gpasswd -d "$agent" sudo
passwd -q -l "$agent"

apt-get -q update
apt-get -q install -y git fd-find tmux nftables

# Every login shell: Lab's guest tools on PATH, and each key lab placed in
# ~/.lab/keys exported under its file's name.
cat > /etc/profile.d/lab.sh <<'PROFILE'
PATH="/lab/bin:$PATH"
for f in "$HOME"/.lab/keys/*; do
  [ -f "$f" ] && export "${f##*/}=$(cat "$f")"
done
unset f
PROFILE

# The egress fence: replies and loopback pass, everything private is
# rejected (not dropped - a probe should see the fence, not a timeout).
cat > /etc/nftables.conf <<'NFT'
#!/usr/sbin/nft -f
flush ruleset

table inet lab {
  chain output {
    type filter hook output priority 0; policy accept;
    ct state established,related accept
    oif "lo" accept
    ip daddr {
      10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
      169.254.0.0/16, 100.64.0.0/10, 224.0.0.0/4
    } reject
  }
}
NFT
systemctl enable --now nftables
nft -f /etc/nftables.conf

# What the guest needs to know about how it was built: the agent, mixins,
# and default harness. verify.sh reads this; no name is hard-coded.
{
  printf 'LAB_AGENT=%q\n' "$agent"
  printf 'LAB_MIXINS=%q\n' "$PARAM_LabMixins"
  printf 'LAB_HARNESS=%q\n' "$PARAM_LabHarness"
} > /etc/lab.env
