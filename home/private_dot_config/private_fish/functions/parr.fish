function parr -d "par2 protect a directory (10% recovery, for data leaving btrfs)"
    if test (count $argv) -eq 0
        echo "usage: parr DIR        # repair later: par2 repair DIR.par2" >&2
        return 1
    end
    set -l src (string trim -r -c / $argv[1])
    par2 create -r10 -R $src.par2 $src
end
