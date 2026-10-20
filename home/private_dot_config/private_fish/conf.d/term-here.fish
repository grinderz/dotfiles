# Inside zellij the shell is a child of the zellij server, so term-here
# (sway $mod+Return) cannot find it under the focused window; record the
# cwd at every prompt instead, the pane being typed in is the last one
# that drew a prompt. One tmpfs write per prompt, linux only.
function __term_here_cwd --on-event fish_prompt
    set -q ZELLIJ; and set -q XDG_RUNTIME_DIR; or return
    echo $PWD > $XDG_RUNTIME_DIR/term-here-cwd
end
