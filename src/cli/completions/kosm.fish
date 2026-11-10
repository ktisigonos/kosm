# Completions for kosm in fish. Install them with:
#   kosm completions fish > ~/.config/fish/completions/kosm.fish

function __kosm_complete
    set -l words (commandline -opc)
    set -l current (commandline -ct)
    if test "$words[-1]" = --config
        __fish_complete_directories "$current"
        return
    end
    kosm complete -- $words[2..-1] "$current" 2>/dev/null
end

complete -c kosm -f -a '(__kosm_complete)'
