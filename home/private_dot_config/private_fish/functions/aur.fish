function aur -d "build and install one of the own PKGBUILDs in ~/src/personal/aur, or clean up after them"
    set -l repo ~/src/personal/aur
    # the operations are yay's, for the hand that already knows them; a bare
    # package name is -S
    switch "$argv[1]"
        case -Sc --clean
            if test (count $argv) -eq 1
                __aur_clean $repo
                return
            end
            set argv
        case -S
            set -e argv[1]
    end
    if test (count $argv) -ne 1; or string match -q -- '-*' $argv[1]
        echo "usage: aur -S PACKAGE     # build and install a directory under ~/src/personal/aur" >&2
        echo "       aur PACKAGE        # the same" >&2
        echo "       aur -Sc            # clean what the builds left, as yay -Sc does for the AUR" >&2
        return 2
    end
    set -l dir $repo/$argv[1]
    test -f $dir/PKGBUILD; or begin
        echo "aur: no PKGBUILD in $dir" >&2
        return 1
    end
    # -B alone only builds; -i is what installs the result
    yay -Bi $dir
end

# yay -Sc cleans the AUR builds in ~/.cache/yay. The builds from the own
# repository go to ~/.cache/makepkg instead (~/.config/pacman/makepkg.conf),
# where nothing else cleans. This removes the same things yay would: build
# trees, built packages and downloaded sources. A VCS clone that a PKGBUILD
# in the repository still names stays, it is what is slow to fetch again.
function __aur_clean -a repo
    set -l cache ~/.cache/makepkg
    set -q XDG_CACHE_HOME; and set cache $XDG_CACHE_HOME/makepkg
    if not test -d $cache
        echo "aur: nothing to clean, $cache does not exist"
        return 0
    end

    # the directory makepkg clones a VCS source into: the name before ::, or
    # the last part of the URL without .git, its #fragment and ?query
    set -l keep
    for src in (cat $repo/*/.SRCINFO 2>/dev/null | string match -rg '^\s*source(?:_\w+)? = (.+)$')
        set -l parts (string split -m1 '::' -- $src)
        string match -qr '^(git|hg|svn|bzr|fossil)(\+|://)' -- $parts[-1]; or continue
        if test (count $parts) -eq 2
            set -a keep $parts[1]
        else
            set -a keep (string replace -r '[#?].*$' '' -- $parts[-1] | string replace -r '/+$' '' \
                | path basename | string replace -r '\.git$' '')
        end
    end

    set -l victims $cache/build/* $cache/packages/*
    for s in $cache/sources/*
        contains -- (path basename $s) $keep; or set -a victims $s
    end
    if test (count $victims) -eq 0
        echo "aur: nothing to clean in $cache"
        return 0
    end

    du -sh -- $victims
    for k in $keep
        test -e $cache/sources/$k; and echo "kept: $cache/sources/$k"
    end
    read -l -P "aur: remove the above? [y/N] " answer; or return 1
    string match -qir '^y(es)?$' -- $answer; or return 1
    rm -rf -- $victims
end
