package main

import "core:fmt"
import "core:strings"

// Returns whether a bang trigger or alias matches the prefix currently being completed.
// The configured user-facing bang prefix is ignored. An empty prefix matches everything.
completion_key_matches :: proc(key, input_prefix: string) -> bool {
	prefix := strings.trim_space(input_prefix)
	user_prefix := get_bang_prefix()

	if strings.has_prefix(prefix, user_prefix) do prefix = prefix[len(user_prefix):]
	if len(prefix) == 0 do return true
	return ascii_has_prefix_fold(key, prefix)
}

// Prints bang completion candidates. Aliases are emitted as separate candidates, and identify
// their primary trigger in the desc. Optional prefix can be used to avoid sending entire bang database
// to the shell on every request
print_bang_completions :: proc(bangs: []Bang, input_prefix: string = "") {
	user_prefix := get_bang_prefix()

	for bang in bangs {
		if completion_key_matches(bang.trigger, input_prefix) {
			fmt.printfln("%s%s\t%s", user_prefix, bang.trigger, bang.name)
		}
		for alias in bang.triggers {
			if completion_key_matches(alias, input_prefix) {
				fmt.printfln(
					"%s%s\t%s (alias for %s%s)",
					user_prefix,
					alias,
					bang.name,
					user_prefix,
					bang.trigger,
				)
			}
		}
	}
}
// Generate Zsh completion definition.
// Intended usage:
//     obang completions zsh > ~/.zfunc/_obang
print_zsh_completions :: proc() {
	fmt.print(
		`#compdef obang

_obang() {
    local cur
    cur="${words[CURRENT]}"

    if (( CURRENT == 2 )); then
        _values "obang command" \
            "cmd:Resolve and open a bang" \
            "runner:Open a runner as a bang input box" \
            "browse:Browse and search bangs" \
            "search:Fuzzy-search bang names" \
            "get:Get a bang by trigger or alias" \
            "count:Print the number of cached bangs" \
            "update:Update the Kagi bang database" \
            "completions:Generate shell completions" \
            "help:Show help" \
            "-c:Resolve and open a bang" \
            "-r:Open a runner as a bang input box" \
            "-b:Browse bangs" \
            "-s:Fuzzy-search bang names" \
            "-g:Get a bang by trigger or alias" \
            "-n:Print bang count" \
            "-u:Update database" \
            "-h:Show help" \
            "--command:Resolve and open a bang" \
            "--runner:Open runner" \
            "--browse:Browse bangs" \
            "--search:Search bangs" \
            "--get:Get bang" \
            "--update:Update database" \
            "--help:Show help"
        return
    fi

    case "${words[2]}" in
        -c|cmd|--command)
            local -a bangs
            local value description

            while IFS=$'\t' read -r value description; do
                [[ -n "$value" ]] && bangs+=("${value}:${description}")
            done < <(obang __complete-bangs "$cur")

            _describe "bang" bangs
            ;;

        -g|get|--get)
            if [[ "$cur" == -* ]]; then
                _values "option" \
                    "-j:Output JSON" \
                    "--json:Output JSON"
                return
            fi

            local -a bangs
            local value description

            while IFS=$'\t' read -r value description; do
                [[ -n "$value" ]] && bangs+=("${value}:${description}")
            done < <(obang __complete-bangs "$cur")

            _describe "bang" bangs
            ;;

        completions)
            _values "shell" \
                "fish:Fish shell" \
                "bash:Bash shell" \
                "zsh:Zsh shell"
            ;;
    esac
}

compdef _obang obang
`,
	)
}


// Generate Bash completion definition.
// Intended usage:
//     obang completions bash > ~/.local/share/bash-completion/completions/obang
print_bash_completions :: proc() {
	fmt.print(
		`_obang_complete() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=($(compgen -W \
            "cmd runner browse search get count update completions help \
             -c -r -b -s -g -n -u -h \
             --command --runner --browse --search --get --update --help" \
            -- "$cur"))
        return
    fi

    case "${COMP_WORDS[1]}" in
        -c|cmd|--command)
            local value
            COMPREPLY=()

            while IFS=$'\t' read -r value _; do
                [[ -n "$value" ]] && COMPREPLY+=("$value")
            done < <(obang __complete-bangs "$cur")
            ;;

        -g|get|--get)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-j --json" -- "$cur"))
                return
            fi

            local value
            COMPREPLY=()

            while IFS=$'\t' read -r value _; do
                [[ -n "$value" ]] && COMPREPLY+=("$value")
            done < <(obang __complete-bangs "$cur")
            ;;

        completions)
            COMPREPLY=($(compgen -W "fish bash zsh" -- "$cur"))
            ;;
    esac
}

complete -F _obang_complete obang
`,
	)
}


// Generate Fish completion definition.
// Intended usage:
//     obang completions fish > ~/.config/fish/completions/obang.fish
print_fish_completions :: proc() {
	fmt.print(
		`function __obang_complete_bangs
    set -l prefix (commandline -ct)
    obang __complete-bangs "$prefix"
end

function __obang_at_root
    set -l words (commandline -opc)
    test (count $words) -eq 1
end

function __obang_wants_bang
    set -l words (commandline -opc)

    if test (count $words) -lt 2
        return 1
    end

    switch $words[2]
        case -c cmd --command -g get --get
            return 0
    end

    return 1
end

function __obang_after_completions
    set -l words (commandline -opc)
    test (count $words) -ge 2; and test "$words[2]" = completions
end

complete -c obang -f

complete -c obang -n '__obang_at_root' -a 'cmd'         -d 'Resolve and open a bang'
complete -c obang -n '__obang_at_root' -a 'runner'      -d 'Open the configured runner as a bang input box'
complete -c obang -n '__obang_at_root' -a 'browse'      -d 'Browse and search bangs in a runner menu'
complete -c obang -n '__obang_at_root' -a 'search'      -d 'Fuzzy-search bang names'
complete -c obang -n '__obang_at_root' -a 'get'         -d 'Get a bang by trigger or alias'
complete -c obang -n '__obang_at_root' -a 'count'       -d 'Print the number of cached bangs'
complete -c obang -n '__obang_at_root' -a 'update'      -d 'Update the Kagi bang database'
complete -c obang -n '__obang_at_root' -a 'completions' -d 'Print shell completions'
complete -c obang -n '__obang_at_root' -a 'help'        -d 'Show help'

complete -c obang -n '__obang_at_root' -a '-c' -d 'Resolve and open a bang'
complete -c obang -n '__obang_at_root' -a '-r' -d 'Open a runner as a bang input box'
complete -c obang -n '__obang_at_root' -a '-b' -d 'Browse bangs in a runner menu'
complete -c obang -n '__obang_at_root' -a '-s' -d 'Fuzzy-search bang names'
complete -c obang -n '__obang_at_root' -a '-g' -d 'Get a bang by trigger or alias'
complete -c obang -n '__obang_at_root' -a '-n' -d 'Print the number of cached bangs'
complete -c obang -n '__obang_at_root' -a '-u' -d 'Update the Kagi bang database'
complete -c obang -n '__obang_at_root' -a '-h' -d 'Show help'

complete -c obang \
    -n '__obang_wants_bang' \
    -a '(__obang_complete_bangs)'

complete -c obang \
    -n '__obang_after_completions' \
    -a 'fish bash zsh' \
    -d 'Shell completions'
`,
	)
}
