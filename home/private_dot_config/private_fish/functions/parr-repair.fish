function parr-repair -d "repair every damaged per-file par2 set under DIR"
    if test (count $argv) -eq 0
        echo "usage: parr-repair DIR" >&2
        return 1
    end
    for p in (find (string trim -r -c / $argv[1]) -name '*.par2' ! -name '*.vol*')
        set -l data (string replace -r '\.par2$' '' $p)
        test -e "$data"; or continue    # orphan: nothing to repair
        if not par2 verify -qq -- "$p" >/dev/null 2>&1
            echo "repairing: $p"
            par2 repair -q -- "$p"
        end
    end
end
