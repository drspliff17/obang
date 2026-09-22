package main

import "core:fmt"
import "core:strings"

completion_key_matches :: proc(key, input_prefix: string) -> bool {
	prefix := strings.trim_space(input_prefix)
	if len(prefix) > 0 && prefix[0] == '!' do prefix = prefix[1:]
	if len(prefix) == 0 do return true
	return ascii_has_prefix_fold(key, prefix)
}

print_bang_completions :: proc(bangs: []Bang, prefix: string = "") {
	for bang in bangs {
		if completion_key_matches(bang.trigger, prefix) {
			fmt.printfln("!%s\t%s", bang.trigger, bang.name)
		}

		for alias in bang.triggers {
			if completion_key_matches(alias, prefix) {
				fmt.printfln("!%s\t%s (alias for !%s)", alias, bang.name, bang.trigger)
			}
		}
	}
}

print_fish_completions :: proc() {
	fmt.println("function __obang_complete_bangs")
	fmt.println("    set -l prefix (commandline -ct)")
	fmt.println("    obang __complete-bangs \"$prefix\"")
	fmt.println("end")
	fmt.println("")

	fmt.println("function __obang_at_root")
	fmt.println("    set -l words (commandline -opc)")
	fmt.println("    test (count $words) -eq 1")
	fmt.println("end")
	fmt.println("")

	fmt.println("function __obang_wants_bang")
	fmt.println("    set -l words (commandline -opc)")
	fmt.println("    if test (count $words) -lt 2")
	fmt.println("        return 1")
	fmt.println("    end")
	fmt.println("    switch $words[2]")
	fmt.println("        case -c cmd --command -g get --get")
	fmt.println("            return 0")
	fmt.println("    end")
	fmt.println("    return 1")
	fmt.println("end")
	fmt.println("")

	fmt.println("function __obang_after_completions")
	fmt.println("    set -l words (commandline -opc)")
	fmt.println("    test (count $words) -ge 2; and test \"$words[2]\" = completions")
	fmt.println("end")
	fmt.println("")

	fmt.println("complete -c obang -f")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'cmd' -d 'Resolve and open a bang'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'runner' -d 'Open the configured runner as a bang input box'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'browse' -d 'Browse and search bangs in a runner menu'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'search' -d 'Fuzzy-search bang names'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'get' -d 'Get a bang by trigger or alias'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'count' -d 'Print the number of cached bangs'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'update' -d 'Update the Kagi bang database'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'completions' -d 'Print shell completions'")
	fmt.println("complete -c obang -n '__obang_at_root' -a 'help' -d 'Show help'")
	fmt.println("")

	fmt.println("complete -c obang -n '__obang_at_root' -a '-c' -d 'Resolve and open a bang'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-r' -d 'Open a runner as a bang input box'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-b' -d 'Browse bangs in a runner menu'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-s' -d 'Fuzzy-search bang names'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-g' -d 'Get a bang by trigger or alias'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-n' -d 'Print the number of cached bangs'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-u' -d 'Update the Kagi bang database'")
	fmt.println("complete -c obang -n '__obang_at_root' -a '-h' -d 'Show help'")
	fmt.println("")

	fmt.println("complete -c obang -n '__obang_wants_bang' -a '(__obang_complete_bangs)'")
	fmt.println("complete -c obang -n '__obang_after_completions' -a 'fish' -d 'Fish shell completions'")
}
