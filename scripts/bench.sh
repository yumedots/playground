#!/bin/sh
set -u

SECS=${BENCH_SECS:-15}
SOCK=${TMPDIR:-/tmp}/tryBench.$$
SSH="sshpass -p alarm ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ControlMaster=auto -o ControlPath=$SOCK -o ControlPersist=120 -p 2222 alarm@127.0.0.1"
GUEST='export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1);'
PID=$(pgrep -x qemu-system-aarch64 | head -1)
[ -n "$PID" ] || { echo "no qemu-system-aarch64 running, start xmake vm first" >&2; exit 1; }
command -v sshpass >/dev/null || { echo "sshpass missing" >&2; exit 1; }
trap '$SSH -O exit 2>/dev/null; rm -f "$SOCK"' EXIT

guest() {
  $SSH "$GUEST $1"
}

hostCpu() {
  top -l $((SECS + 1)) -s 1 -pid "$PID" -stats cpu,power 2>/dev/null |
    awk '$1 ~ /^[0-9.]+$/ { n++; if (n > 1) { cpu += $1; power += $2; c++ } } END { printf "%.0f %.0f", cpu / c, power / c }'
}

hostGpu() {
  for i in $(seq "$SECS"); do
    ioreg -r -d 1 -c IOAccelerator | sed -n 's/.*"Device Utilization %"=\([0-9]*\).*/\1/p' | head -1
    sleep 1
  done | awk '{ s += $1; c++ } END { printf "%.0f", s / c }'
}

guestTop() {
  guest "top -bn2 -d$SECS -o %CPU -w 200 | awk '/^top -/ { n++ } n == 2 && \$1 ~ /^[0-9]+\$/ && \$9 + 0 >= 0.5 { printf \"%s %s%%  \", \$12, \$9 }' | cut -c1-120"
}

measure() {
  name=$1
  extra=$2
  hostCpu > "$SOCK.cpu" &
  hostGpu > "$SOCK.gpu" &
  procs=$(guestTop)
  wait
  read -r cpu power < "$SOCK.cpu"
  printf '%-11s qemu %4s%%  energy %5s  host gpu %3s%%  %s\n' "$name" "$cpu" "$power" "$(cat "$SOCK.gpu")" "$extra"
  printf '%-11s guest: %s\n' "" "${procs:-idle}"
  rm -f "$SOCK.cpu" "$SOCK.gpu"
}

focus() {
  echo "hyprctl dispatch 'hl.dsp.focus({ workspace = $1 })' >/dev/null;"
}

spawn() {
  echo "hyprctl eval 'hl.exec_cmd(\"$1\")' >/dev/null;"
}

osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" >/dev/null
guest "command -v glmark2-es2-wayland >/dev/null || echo root | su -c 'pacman -S --needed --noconfirm glmark2 mesa-utils >/dev/null 2>&1' root 2>/dev/null"
guest "$(focus 1) pkill -x foot; pkill -f gears; pkill -f glmark2; true"
info=$(guest "hyprctl monitors | sed -n '2p;/scale:/p' | tr -s ' \t' ' '; grep -m1 -o 'Renderer: [^)]*)' /run/user/1000/hypr/*/hyprland.log; printf 'while :; do seq 1 200000; done\n' > /tmp/flood.sh")
echo "$(echo "$info" | tr '\n' ' ')$SECS s per scenario"
sleep 3
measure idle ""

guest "$(spawn "foot sh /tmp/flood.sh")"
sleep 3
measure terminal "foot printing seq in a loop"
guest "pkill -x foot"

guest "$(spawn foot) $(spawn foot) sleep 2; $(focus 2) $(spawn foot) sleep 2"
guest "end=\$((\$(date +%s) + $SECS + 4)); while [ \$(date +%s) -lt \$end ]; do $(focus 2) sleep 0.2; $(focus 1) sleep 0.2; done" &
sleep 2
measure workspaces "switching every 0.2s with 3 foot windows"
wait
guest "pkill -x foot; $(focus 1)"

guest "stdbuf -oL es2gears_wayland > /tmp/gears.log 2>&1 &"
sleep 3
measure gears ""
fps=$(guest "grep -o '[0-9.]* FPS' /tmp/gears.log | tail -2 | tr '\n' ' '; pkill -f es2gears")
echo "            es2gears: $fps"

guest "glmark2-es2-wayland -b build:duration=$SECS > /tmp/glmark.log 2>&1 &"
sleep 3
measure glmark2 ""
sleep 3
score=$(guest "grep -E 'FPS:' /tmp/glmark.log | tail -1")
echo "            glmark2 build: ${score:-not finished}"
guest "pkill -f glmark2; true"
