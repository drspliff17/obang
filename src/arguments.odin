package main

import "core:fmt"
import "core:os"
import "core:strings"

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

			fox_type := "--new-window"
			if a[0] == "-t" || a[0] == "tab" {
				fox_type = "--new-tab"
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

			_, start_err := os.process_start(
				os.Process_Desc{command = []string{"firefox", fox_type, url}},
			)
			if start_err != nil {
				fmt.eprintfln("Failed to start Firefox: %v", start_err)
				return false
			}

			return true

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
