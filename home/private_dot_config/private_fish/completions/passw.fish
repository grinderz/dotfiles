# Completions for passw (pass against the work store): entry paths come
# straight from the store tree, subcommands mirror pass.
function __passw_entries
    set -l store $HOME/sync/work/pass
    find $store -name '*.gpg' -type f 2>/dev/null \
        | string replace "$store/" '' \
        | string replace -r '\.gpg$' ''
end

complete -c passw -f
complete -c passw -n __fish_use_subcommand \
    -a 'show insert edit generate rm mv cp ls find grep git help' -d subcommand
complete -c passw -a '(__passw_entries)'
