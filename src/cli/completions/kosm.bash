# Completions for kosm in bash. Install them with:
#   kosm completions bash > ~/.local/share/bash-completion/completions/kosm

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
