function aur -d "build and install one of the own PKGBUILDs in ~/src/personal/aur"
    if test (count $argv) -ne 1
        echo "usage: aur PACKAGE        # a directory under ~/src/personal/aur" >&2
        return 2
    end
    set -l dir ~/src/personal/aur/$argv[1]
    test -f $dir/PKGBUILD; or begin
        echo "aur: no PKGBUILD in $dir" >&2
        return 1
    end
    # -B alone only builds; -i is what installs the result
    yay -Bi $dir
end
