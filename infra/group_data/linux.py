# defaults, override per-host in inventory.py
pacman_conf_parallel_downloads = 10
pacman_conf_no_extract = [
    "usr/lib/binfmt.d/wine.conf",
    "usr/share/applications/wine.desktop",
    "usr/share/applications/libreoffice-*.desktop",
    "usr/share/dbus-1/services/org.a11y.*",
    "etc/cron.hourly/snapper",
]

systemd_journal_system_max_use = "100M"
systemd_network_wired_dock_match_name = None
