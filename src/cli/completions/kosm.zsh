#compdef kosm
# Completions for kosm in zsh. Install them with:
#   kosm completions zsh > <a directory in $fpath>/_kosm

_kosm() {
    if [[ "${words[CURRENT-1]}" == --config ]]; then
        _files -/
        return
    fi
    local -a plain paths
    local line
    for line in "${(@f)$(kosm complete -- "${(@)words[2,CURRENT]}" 2>/dev/null)}"; do
        [[ -z "$line" ]] && continue
        # A --set path ends in =, and its value follows without a space.
        if [[ "${line%%$'\t'*}" == *= ]]; then
            paths+=("${line/$'\t'/:}")
        else
            plain+=("${line/$'\t'/:}")
        fi
    done
    (( ${#paths} )) && _describe -t paths 'path' paths -S ''
    (( ${#plain} )) && _describe -t candidates 'kosm' plain
}

_kosm "$@"
