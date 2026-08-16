function parr-verify -d "verify every per-file par2 set under DIR"
    if test (count $argv) -eq 0
        echo "usage: parr-verify DIR" >&2
        return 1
    end
    set -l bad 0
    for p in (find (string trim -r -c / $argv[1]) -name '*.par2' ! -name '*.vol*')
        set -l data (string replace -r '\.par2$' '' $p)
        if not test -e "$data"
            echo "orphan: $p (data gone, unrecoverable set — clean it up)"
            continue
        end
        if not par2 verify -qq -- "$p" >/dev/null 2>&1
            echo "DAMAGED: $p"
            set bad (math $bad + 1)
        end
    end
    test $bad -eq 0; and echo "all sets ok"; or begin
        echo "$bad damaged set(s) — parr-repair to fix" >&2
        return 1
    end
end
