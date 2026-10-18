# Right prompt: the time the prompt was drawn, to match a command with
# the journal later, and before it how long the last command took once
# that was more than five seconds. The kubectl context used to live here;
# it is on the first line of fish_prompt.fish now (__kube_prompt.fish).

function fish_right_prompt
    set -l parts
    if test "$CMD_DURATION" -ge 5000
        set -l s (math -s0 $CMD_DURATION / 1000)
        if test $s -ge 60
            set -a parts (set_color yellow)(math -s0 $s / 60)"m"(printf %02d (math $s % 60))"s"(set_color normal)
        else
            set -a parts (set_color yellow)$s"s"(set_color normal)
        end
    end
    set -a parts (set_color brblack)(date +%H:%M)(set_color normal)
    string join "  " -- $parts
end
