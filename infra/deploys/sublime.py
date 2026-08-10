from util import block_with_diff

# repo sections are valid at EOF, where files.block appends by default —
# same spot the ansible blockinfile used
block_with_diff(
    name="pacman.conf: sublime-text repo",
    path="/etc/pacman.conf",
    content=[
        "[sublime-text]",
        "Server = https://download.sublimetext.com/arch/stable/x86_64",
    ],
    marker="# {mark} PYINFRA BLOCK sublime-text",
    _sudo=True,
)
