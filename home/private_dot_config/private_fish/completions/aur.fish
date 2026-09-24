# the package directories of ~/src/personal/aur
complete -c aur -f -a '(for d in ~/src/personal/aur/*/PKGBUILD; basename (dirname $d); end)'
