function rhashr -d "sha256 hash file for DIR (incremental via --update)"
    if test (count $argv) -eq 0
        echo "usage: rhashr DIR" >&2
        return 1
    end
    set -l src (string trim -r -c / $argv[1])
    if test -e "$src.sha256"
        rhash -r --sha256 --update="$src.sha256" $src
    else
        rhash -r --sha256 -o "$src.sha256" $src
    end
end
