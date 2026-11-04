#!/system/bin/sh

# Preserve recovery diagnostics on Selene's rescue partition, mounted at /cache.
# Keep a staging copy in /tmp until /cache is mounted so early pstore data survives.

PATH=/sbin:/system/bin:/system/xbin
export PATH

STAGE=/tmp/ofox-debug-stage
RESCUE=/dev/block/platform/bootdevice/by-name/rescue
BASE=/cache/ofox-debug
STAMP=$(date -u +%Y%m%d-%H%M%S 2>/dev/null)
[ -n "$STAMP" ] || STAMP="uptime-$(cut -d ' ' -f 1 /proc/uptime 2>/dev/null | tr -d '.')"
OUT="$BASE/boot-$STAMP"

mkdir -p "$STAGE"
LOGFILE="$STAGE/collector.log"
exec >>"$LOGFILE" 2>&1
echo "OFOX log collector started: $STAMP"

mkdir -p /sys/fs/pstore
mount -t pstore pstore /sys/fs/pstore 2>/dev/null || true

start_logcat_stream() {
    [ "$LOGCAT_STARTED" = "1" ] && return
    logcat -b all -v threadtime -f "$DEST/logcat-live.txt" -r 2048 -n 3 \
        >>"$LOGFILE" 2>&1 &
    LOGCAT_PID=$!
    LOGCAT_STARTED=1
    echo "continuous logcat started: pid=$LOGCAT_PID"
}

snapshot() {
    dest="$1"
    mkdir -p "$dest"

    dmesg > "$dest/kernel-dmesg.txt.tmp" 2>>"$LOGFILE" && \
        mv "$dest/kernel-dmesg.txt.tmp" "$dest/kernel-dmesg.txt"
    logcat -b all -d -v threadtime > "$dest/logcat.txt.tmp" 2>>"$LOGFILE" && \
        mv "$dest/logcat.txt.tmp" "$dest/logcat.txt"
    getprop > "$dest/properties.txt.tmp" 2>>"$LOGFILE" && \
        mv "$dest/properties.txt.tmp" "$dest/properties.txt"

    cat /proc/cmdline > "$dest/proc-cmdline.txt" 2>/dev/null
    cat /proc/bootconfig > "$dest/proc-bootconfig.txt" 2>/dev/null || true
    cat /proc/mounts > "$dest/proc-mounts.txt" 2>/dev/null
    cat /proc/partitions > "$dest/proc-partitions.txt" 2>/dev/null
    cat /proc/meminfo > "$dest/proc-meminfo.txt" 2>/dev/null
    cat /proc/interrupts > "$dest/proc-interrupts.txt" 2>/dev/null
    cat /proc/sys/kernel/printk > "$dest/kernel-printk.txt" 2>/dev/null
    cat /proc/last_kmsg > "$dest/last_kmsg.txt" 2>/dev/null || true

    for f in /tmp/recovery.log /tmp/last_log /tmp/last_install /tmp/fox.log /tmp/twrp.log \
             /cache/recovery/log /cache/recovery/last_log /cache/recovery/last_install; do
        if [ -f "$f" ]; then
            name=$(basename "$f")
            cp -f "$f" "$dest/$name" 2>/dev/null || true
        fi
    done

    mkdir -p "$dest/pstore"
    for f in /sys/fs/pstore/*; do
        [ -f "$f" ] || continue
        cp -f "$f" "$dest/pstore/$(basename "$f")" 2>/dev/null || true
    done

    for dir in /tmp/tombstones /data/tombstones /cache/tombstones; do
        [ -d "$dir" ] || continue
        mkdir -p "$dest/tombstones/$(basename "$dir")"
        for f in "$dir"/*; do
            [ -f "$f" ] && cp -f "$f" "$dest/tombstones/$(basename "$dir")/" 2>/dev/null
        done
    done

    echo "snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" > "$dest/collector-status.txt"
}

# Capture the previous kernel's persistent crash records before other services can rotate them.
snapshot "$STAGE"

# init mounts rescue as /cache during late-fs. Wait for that mount, then mount it
# ourselves as a fallback if init did not do so.
tries=0
while ! grep -q ' /cache ' /proc/mounts 2>/dev/null && [ "$tries" -lt 30 ]; do
    if [ $((tries % 5)) -eq 0 ]; then snapshot "$STAGE"; fi
    sleep 1
    tries=$((tries + 1))
done

if ! grep -q ' /cache ' /proc/mounts 2>/dev/null && [ -b "$RESCUE" ]; then
    mkdir -p /cache
    mount -t ext4 -o rw,noatime,nosuid,nodev "$RESCUE" /cache 2>>"$LOGFILE" || true
fi

if grep -q ' /cache ' /proc/mounts 2>/dev/null; then
    mkdir -p "$OUT"
    cp -Rf "$STAGE"/. "$OUT"/
    LOGFILE="$OUT/collector.log"
    exec >>"$LOGFILE" 2>&1
    chmod -R 0777 "$BASE" 2>/dev/null || true
    DEST="$OUT"
    echo "Persistent logs: $OUT"
    start_logcat_stream
else
    DEST="$STAGE"
    echo "WARNING: /cache (rescue) is not mounted; logs are only staged in /tmp"
fi

# Snapshot often enough to survive a forced reboot while avoiding continuous writes.
while true; do
    sleep 15
    snapshot "$DEST"
    if [ "$DEST" = "$STAGE" ] && grep -q ' /cache ' /proc/mounts 2>/dev/null; then
        mkdir -p "$OUT"
        cp -Rf "$STAGE"/. "$OUT"/
        LOGFILE="$OUT/collector.log"
        exec >>"$LOGFILE" 2>&1
        chmod -R 0777 "$BASE" 2>/dev/null || true
        DEST="$OUT"
        echo "Persistent logs: $OUT"
        start_logcat_stream
    fi
    sync
done
