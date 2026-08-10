function zl-layout
    zellij attach $argv[1] 2>/dev/null; or zellij -n $argv[1] -s $argv[1]
end
