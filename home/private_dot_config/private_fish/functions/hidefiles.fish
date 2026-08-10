function hidefiles
    defaults write com.apple.finder AppleShowAllFiles false; and killall Finder
end
