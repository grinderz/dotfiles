function rhash-verify -d "verify DIR against DIR.sha256; lists missing files"
    if test (count $argv) -eq 0
        echo "usage: rhash-verify DIR" >&2
        return 1
    end
    set -l src (string trim -r -c / $argv[1])
    rhash -c "$src.sha256"
    set -l rc $status
    set -l missing (rhash --missing="$src.sha256" 2>/dev/null)
    if test -n "$missing"
        echo "missing files:" >&2
        printf '%s\n' $missing >&2
    end
    return $rc
end
