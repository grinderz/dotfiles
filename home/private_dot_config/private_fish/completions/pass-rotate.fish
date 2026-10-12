# Completions for pass-rotate: entries from both stores (personal and
# work), the flags from its usage line.
function __pass_rotate_entries
    for store in $HOME/sync/pass $HOME/sync/work/pass
        find $store -name '*.gpg' -type f 2>/dev/null \
            | string replace "$store/" '' \
            | string replace -r '\.gpg$' ''
    end
end

complete -c pass-rotate -f
complete -c pass-rotate -s n -d 'plan only, print would run'
complete -c pass-rotate -s i -d 'insert -f the entry first'
complete -c pass-rotate -s c -x -a 'passp passw pass' -d 'store command'
complete -c pass-rotate -a '(__pass_rotate_entries)'
