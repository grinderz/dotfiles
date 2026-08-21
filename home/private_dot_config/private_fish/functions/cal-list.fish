function cal-list --description 'calendars per account, from the vdirsyncer tree'
    for d in ~/.local/share/calendars/*/*/
        set -l acc (basename (dirname $d))
        set -l name (cat $d/displayname 2>/dev/null; or basename $d)
        printf '%-12s %s\n' $acc "$name"
    end
end
