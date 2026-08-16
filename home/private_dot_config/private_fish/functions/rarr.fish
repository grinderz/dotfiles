function rarr -d "rar directory with 10% recovery record"
    if test (count $argv) -eq 0
        echo "usage: rarr DIR" >&2
        return 1
    end
    set -l src (string trim -r -c / $argv[1])
    rar a -r -rr10p $src.rar $src
end
