function extract -d "unpack an archive by its extension (tar.zst/gz/bz2, zip)"
    switch $argv[1]
        case '*.tar.zst';        zstd -dc $argv[1] | tar -xf -
        case '*.tar.gz' '*.tgz'; tar xzf $argv[1]
        case '*.tar.bz2';        tar xjf $argv[1]
        case '*.zip';            unzip $argv[1]
        case '*';                echo "Don't know how to extract $argv[1]"
    end
end
