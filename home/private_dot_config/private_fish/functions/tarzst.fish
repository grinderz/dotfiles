function tarzst -d "tar directory into .tar.zst"
    if test (count $argv) -eq 0
        echo "usage: tarzst DIR" >&2
        return 1
    end
    set -l src (string trim -r -c / $argv[1])
    tar -cf - $src | zstd -o $src.tar.zst
end
