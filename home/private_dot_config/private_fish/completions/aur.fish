# the package directories of ~/src/personal/aur
complete -c aur -f -a '(for d in ~/src/personal/aur/*/PKGBUILD; basename (dirname $d); end)'
complete -c aur -f -o S -d 'build and install a package'
complete -c aur -f -o Sc -l clean -d 'clean what the builds left in ~/.cache/makepkg'
