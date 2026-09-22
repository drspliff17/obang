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
			if len(a) < 2 {
				fmt.eprintfln("Expected bang and query to resolve")
				return false
			}

			fox_type: string
			switch a[0] {
			case "-t", "tab":
				fox_type = "--new-tab"
				a = a[1:]
			case:
				fox_type = "--new-window"
			}

			db := Bang_DB{}
			if !load_bang_db(&db) do return false

			s := strings.join(a[:], " ")
			defer delete_string(s)

			url, ok := resolve_bang(db.data[:], s)
			if !ok {
				fmt.eprintfln("Could not find bang: %s", a[0])
				return false
			}
			_, _ = os.process_start(os.Process_Desc{command = []string{"firefox", fox_type, url}})
			return true

		case "test":
			db := Bang_DB{}
			if !load_bang_db(&db) do return false
			fmt.printfln("Loaded %d bangs", len(db.data))

			str := construct_bang_trigger_list(db.data[:])
			defer if len(str) > 0 do delete_string(str)

			fmt.printfln(str)

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
