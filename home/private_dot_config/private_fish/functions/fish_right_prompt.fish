# Right prompt: what the stock left one leaves out — the kubectl context
# and namespace, so a `kubectl delete` never lands on the wrong cluster,
# and how long the last command took once that was more than five seconds.
#
# `kubectl config view` costs 100–170 ms here, far too much for every
# prompt, so the context is cached and recomputed only when a kubeconfig
# file's mtime moves — which is exactly what use-context and set-context do.
# Cluster rather than context name: an OKD login context is called
# ns/host:port/user, which repeats the namespace and runs half a line.
# A cluster with "prod" in its name is shown in red. What is shown
# follows the width — a zellij split has no room for the full pair:
#   >= 120 columns   ⎈ cluster/namespace
#   >= 80            ⎈ namespace (the colour still says prod or not)
#   narrower         nothing

function fish_right_prompt
    set -l parts

    if set -q KUBECONFIG
        # a list when config.fish set it with --path, one colon-joined
        # string when it came in from the environment; one stat for all
        # of them, a process per file costs ~8 ms each on macOS
        set -l files
        for f in (string split : -- $KUBECONFIG)
            test -r $f; and set -a files $f
        end
        set -l stamp (stat -c %Y $files 2>/dev/null; or stat -f %m $files)
        if test "$stamp" != "$__kube_stamp"
            set -g __kube_stamp $stamp
            set -l out (kubectl config view --minify \
                -o jsonpath='{.contexts[0].context.cluster} {.contexts[0].context.namespace}' 2>/dev/null)
            # the :6443 of an OKD cluster says nothing, drop it
            set -g __kube_cluster (string split ' ' -- $out)[1]
            set -g __kube_cluster (string replace -r ':[0-9]+$' '' -- $__kube_cluster)
            set -g __kube_ns (string split ' ' -- $out)[2]
            test -n "$__kube_ns"; or set -g __kube_ns default
        end
        if test -n "$__kube_cluster"
            set -l color cyan
            string match -q '*prod*' -- $__kube_cluster; and set color red
            set -q COLUMNS; or set -l COLUMNS 200
            if test $COLUMNS -ge 120
                set -a parts (set_color $color)"⎈ $__kube_cluster/$__kube_ns"(set_color normal)
            else if test $COLUMNS -ge 80
                set -a parts (set_color $color)"⎈ $__kube_ns"(set_color normal)
            end
        end
    end

    if test "$CMD_DURATION" -ge 5000
        set -l s (math -s0 $CMD_DURATION / 1000)
        if test $s -ge 60
            set -a parts (set_color yellow)(math -s0 $s / 60)"m"(printf %02d (math $s % 60))"s"(set_color normal)
        else
            set -a parts (set_color yellow)$s"s"(set_color normal)
        end
    end

    string join "  " -- $parts
end
