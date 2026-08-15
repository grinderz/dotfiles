from pyinfra.operations import files

# Only wheel members may even attempt `su` (non-wheel processes cannot
# brute-force the root password). Login/sudo/sshd stacks live in other
# pam.d files and are not touched. Both files are pacman backup= files;
# once uncommented the pattern no longer matches, so re-runs are no-ops.
for pam_file in ('su', 'su-l'):
    files.replace(
        name=f'pam {pam_file}: su for wheel only',
        path=f'/etc/pam.d/{pam_file}',
        text='^#auth           required        pam_wheel.so use_uid$',
        replace='auth            required        pam_wheel.so use_uid',
        _sudo=True,
    )
