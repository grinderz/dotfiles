# The stock fish prompt split over two lines: where you are on the first
# (login, directory, git state, kubectl context), what you type on the
# second. One line ran out of room once the kubectl namespace was a
# branch name. The pipestatus and the root marker stay in front of the
# input, as in the stock prompt, joined by the count of background jobs
# (%2: two suspended or backgrounded processes wait in this shell). The
# kubectl part is __kube_prompt.fish, the git part is fish's own
# fish_vcs_prompt (settings in config.fish).

function fish_prompt --description 'Write out the prompt'
    set -l last_pipestatus $pipestatus
    set -lx __fish_last_status $status # Export for __fish_print_pipestatus.
    set -l normal (set_color --reset)

    # Color the prompt differently when we're root
    set -l color_cwd $fish_color_cwd
    set -l suffix '>'
    if functions -q fish_is_root_user; and fish_is_root_user
        if set -q fish_color_cwd_root
            set color_cwd $fish_color_cwd_root
        end
        set suffix '#'
    end

    # Write pipestatus
    # If the status was carried over (if no command is issued or if `set` leaves the status untouched), don't bold it.
    set -l bold_flag --bold
    set -q __fish_prompt_status_generation; or set -g __fish_prompt_status_generation $status_generation
    if test $__fish_prompt_status_generation = $status_generation
        set bold_flag
    end
    set __fish_prompt_status_generation $status_generation
    set -l status_color (set_color $fish_color_status)
    set -l statusb_color (set_color $bold_flag $fish_color_status)
    set -l prompt_status (__fish_print_pipestatus "[" "]" "|" "$status_color" "$statusb_color" $last_pipestatus)

    set -l kube (__kube_prompt)
    echo -s (prompt_login) ' ' (set_color $color_cwd) (prompt_pwd) $normal (fish_vcs_prompt) $normal (test -n "$kube"; and echo -n "  $kube")
    set -l jobs_n (jobs -p | count)
    set -l jobs_mark
    test $jobs_n -gt 0; and set jobs_mark (set_color yellow) "%$jobs_n " $normal
    echo -n -s $jobs_mark $prompt_status $suffix ' '
end
