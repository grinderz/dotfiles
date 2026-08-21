# Completions for passp (pass against the personal store): entry paths
# come straight from the store tree, subcommands mirror pass.
function __passp_entries
    set -l store $HOME/sync/pass
    find $store -name '*.gpg' -type f 2>/dev/null \
        | string replace "$store/" '' \
        | string replace -r '\.gpg$' ''
end

complete -c passp -f
complete -c passp -n __fish_use_subcommand \
    -a 'show insert edit generate rm mv cp ls find grep git help' -d subcommand
complete -c passp -a '(__passp_entries)'
