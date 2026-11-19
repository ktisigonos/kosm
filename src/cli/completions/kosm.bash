# Completions for kosm in bash. kosm init and kosm update install them into
# ~/.local/share/bash-completion/completions, which bash-completion loads by itself; or print them
# with:
#   kosm completions bash

_kosm() {
    local current="${COMP_WORDS[COMP_CWORD]}"
    if [[ "${COMP_WORDS[COMP_CWORD-1]}" == --config ]]; then
        COMPREPLY=($(compgen -d -- "$current"))
        return
    fi
    local IFS=$'\n'
    local candidates
    candidates="$(kosm complete -- "${COMP_WORDS[@]:1:COMP_CWORD}" 2>/dev/null | cut -f1)"
    COMPREPLY=($(compgen -W "$candidates" -- "$current"))
    # A --set path ends in =, and its value follows without a space.
    [[ "${COMPREPLY[0]}" == *= ]] && compopt -o nospace
}

complete -F _kosm kosm
