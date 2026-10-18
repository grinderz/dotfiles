# The kubectl context for the prompt, so a `kubectl delete` never lands
# on the wrong cluster. Prints nothing without a KUBECONFIG.
#
# `kubectl config view` costs 100–170 ms here, far too much for every
# prompt, so the context is cached and recomputed only when a kubeconfig
# file's mtime moves — which is exactly what use-context and set-context do.
# Cluster rather than context name: an OKD login context is called
# ns/host:port/user, which repeats the namespace and runs half a line.
# A cluster with "prod" in its name is shown in red. What is shown
# follows the width — a zellij split has no room for the full pair:
#   >= 120 columns   ⎈ cluster/namespace
#   narrower         ⎈ namespace (the colour still says prod or not)
# CI namespaces are named after the branch and run to 40+ characters;
# the head says which project, so the namespace is cut to 32 either way.

function __kube_prompt
    set -q KUBECONFIG; or return

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
    test -n "$__kube_cluster"; or return

    set -l color cyan
    string match -q '*prod*' -- $__kube_cluster; and set color red
    set -q COLUMNS; or set -l COLUMNS 200
    set -l ns (string shorten --max 32 -- $__kube_ns)
    if test $COLUMNS -ge 120
        echo -n -s (set_color $color) "⎈ $__kube_cluster/$ns" (set_color normal)
    else
        echo -n -s (set_color $color) "⎈ $ns" (set_color normal)
    end
end
