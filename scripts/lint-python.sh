#!/usr/bin/env bash
# Ruff discovers regular Python files; add scripts identified by their shebang.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
version=${1:?usage: lint-python.sh RUFF_VERSION}

git ls-files --cached --others --exclude-standard -z | {
    args=(.)
    while IFS= read -r -d '' path; do
        case $path in *.py|*.pyi|*.ipynb) continue ;; esac
        [[ -f $path && ! -L $path ]] || continue
        shebang=''
        IFS= read -r -n 256 shebang < "$path" || :
        if [[ $shebang =~ ^\#!.*[[:space:]/]python[0-9.]*([[:space:]]|$) ]]; then
            if [[ $path == *.tmpl ]]; then
                printf '%s: move Python logic to a .py helper and use a shell template\n' "$path" >&2
                exit 1
            fi
            args+=("$path")
        fi
    done
    uvx "ruff@$version" check --force-exclude "${args[@]}"
}
