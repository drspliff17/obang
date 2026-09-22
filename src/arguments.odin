package main

import "core:fmt"
import "core:os"
import "core:strings"

open_firefox :: proc(url: string, new_tab: bool = false) -> bool {
	mode := "--new-window"
	if new_tab do mode = "--new-tab"

	_, start_err := os.process_start(os.Process_Desc{command = []string{"firefox", mode, url}})
	if start_err != nil {
		fmt.eprintfln("Failed to start Firefox: %v", start_err)
		return false
	}

	return true
}

parse_arguments :: proc() -> bool {
	a := os.args[1:]
	if len(a) == 0 {
		fmt.println("Help message will go here")
		return false
	}

	for len(a) > 0 {
		switch a[0] {
		case "-c", "cmd", "--command":
			a = a[1:]
			if len(a) == 0 {
				fmt.eprintln("Expected a bang to resolve")
				return false
			}

			new_tab := false
			if a[0] == "-t" || a[0] == "tab" {
				new_tab = true
				a = a[1:]
				if len(a) == 0 {
					fmt.eprintln("Expected a bang after tab option")
					return false
				}
			}

			db := Bang_DB{}
			if !load_bang_db(&db) do return false

			input := strings.join(a[:], " ")
			defer delete_string(input)

			url, ok := resolve_bang(db.data[:], input)
			if !ok {
				fmt.eprintfln("Could not resolve bang: %s", a[0])
				return false
			}
			defer delete_string(url)

			return open_firefox(url, new_tab)

		case "-r", "runner", "--runner":
			a = a[1:]
			if len(a) == 0 {
				fmt.eprintln("Expected a runner command")
				return false
			}

			runner_input, ok := get_runner_input(a)
			if !ok do return false
			defer delete_string(runner_input)

			db := Bang_DB{}
			if !load_bang_db(&db) do return false

			url, resolved := resolve_bang(db.data[:], runner_input)
			if !resolved {
				fmt.eprintfln("Could not resolve runner output: %s", runner_input)
				return false
			}
			defer delete_string(url)
			return open_firefox(url)

		case "test":
			db := Bang_DB{}
			if !load_bang_db(&db) do return false
			fmt.printfln("Loaded %d bangs", len(db.data))

			str := construct_bang_trigger_list(db.data[:])
			defer if len(str) > 0 do delete_string(str)

			fmt.println(str)
			return true

		case "-u", "update", "--update":
			if !update_kagi_bangs() do return false
			return true

		case:
			fmt.eprintfln("Invalid argument provided: %s", a[0])
			return false
		}
	}

	return true
}
