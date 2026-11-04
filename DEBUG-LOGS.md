# Recovery debug logs

The recovery starts a log collector at `post-fs`. It copies pstore and
`/proc/last_kmsg` early, continuously records logcat with rotation, and refreshes
kernel and recovery log snapshots every 15 seconds. Logs are written to the
Selene `rescue` partition, mounted as `/cache`, so they survive a recovery reboot.

The directory for each boot is:

```text
/cache/ofox-debug/boot-YYYYMMDD-HHMMSS/
```

While the OrangeFox splash is stuck, connect USB and try:

```sh
adb devices
adb pull /cache/ofox-debug ./ofox-debug
```

If ADB is unavailable, enter a working recovery, mount **Cache** (the device's
`rescue` partition), and copy `/cache/ofox-debug` to a PC or external storage.
Do not wipe Cache before copying the logs.

Useful files include `kernel-dmesg.txt`, `logcat-live.txt` (plus its rotated
copies), `logcat.txt`, `recovery.log`,
`last_kmsg.txt`, `pstore/*`, `collector.log`, `proc-cmdline.txt`,
`proc-mounts.txt`, and any `tombstones/*`.

The tree enables logcat, TWRP event logging, `debuggerd`, `strace`, and verbose
kernel printk/initcall output. The collector cannot record a failure that occurs
before recovery init starts unless the kernel preserves it through pstore/ramoops.
The latest snapshot can miss up to about 15 seconds if power is lost abruptly.
