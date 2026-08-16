function parr-each -d "per-file par2 (10%) for every file under DIR; incremental, reports orphans"
    if test (count $argv) -eq 0
        echo "usage: parr-each DIR" >&2
        return 1
    end
    set -l dir (string trim -r -c / $argv[1])
    set -l new 0
    for f in (find $dir -type f ! -name '*.par2')
        if not test -e "$f.par2"
            if par2 create -qq -r10 -- "$f.par2" "$f" >/dev/null
                set new (math $new + 1)
            else
                echo "FAIL: $f" >&2
            end
        end
    end
    echo "protected $new new file(s)"
    for p in (find $dir -name '*.par2' ! -name '*.vol*')
        set -l data (string replace -r '\.par2$' '' $p)
        if not test -e "$data"
            echo "orphan: $p (data gone; rm '$p' '$data'.vol*.par2)"
        end
    end
end
