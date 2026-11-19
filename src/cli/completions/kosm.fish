# Completions for kosm in fish. kosm init and kosm update install them into
# ~/.local/share/fish/vendor_completions.d, which fish loads by itself; or print them with:
#   kosm completions fish

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
