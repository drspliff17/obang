package main

//TODO:
// Add comments, cleanup && formatting wherever i cocked up
// Implement config for loading custom bangs, and defining constant runner cmds

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	a := os.args[1:]
	if len(a) == 0 {
		print_help()
		return
	}

	switch a[0] {
	case "-h", "help", "--help":
		print_help()
		return

	case "-c", "cmd", "--command":
		a = a[1:]
		if len(a) == 0 {
			fmt.eprintln("Expected a bang to resolve")
			return
		}

		new_tab := false
		if a[0] == "-t" || a[0] == "tab" {
			new_tab = true
			a = a[1:]
			if len(a) == 0 {
				fmt.eprintln("Expected a bang after tab option")
				return
			}
		}

		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)

		input := strings.join(a[:], " ")
		defer delete_string(input)

		url, ok := resolve_bang(db.data[:], input)
		if !ok {
			fmt.eprintfln("Could not resolve bang: %s", input)
			return
		}
		defer delete_string(url)

		open_firefox(url, new_tab)
		return

	case "-r", "runner", "--runner":
		a = a[1:]
		if len(a) == 0 {
			fmt.eprintln("Expected a runner command")
			return
		}

		runner_input, ok := get_runner_input(a)
		if !ok do return
		defer delete_string(runner_input)

		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)

		url, resolved := resolve_bang(db.data[:], runner_input)
		if !resolved {
			b, ok := terminal_get_bang(db.data[:], "!g")
			if !ok do fmt.eprintfln("Could not resolve runner output: %s", runner_input)

			//TODO: Hook this default to Google Search behaviour into some config flag
			url = resolve_template(b.template, runner_input)
			open_firefox(url)
			delete_string(url)
			return
			// fmt.eprintfln("Could not resolve runner output: %s", runner_input)
			// return
		}
		defer delete_string(url)

		open_firefox(url)
		return

	case "-b", "browse", "--browse":
		a = a[1:]
		if len(a) == 0 {
			fmt.eprintln("Expected a runner command")
			return
		}

		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)

		browse_bangs(&db, a)
		return

	case "-s", "search", "--search":
		a = a[1:]
		if len(a) == 0 {
			fmt.eprintln("Expected a bang name to search for")
			return
		}

		query := strings.join(a, " ")
		defer delete_string(query)

		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)

		terminal_search(&db, query)
		return

	case "-g", "get", "--get":
		a = a[1:]
		if len(a) == 0 {
			fmt.eprintln("Expected a bang trigger or alias")
			return
		}

		json_output := false

		if a[0] == "-j" || a[0] == "--json" {
			json_output = true
			a = a[1:]

			if len(a) == 0 {
				fmt.eprintln("Expected a bang trigger or alias")
				return
			}
		}

		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)

		terminal_get(&db, a[0], json_output)
		return

	case "-n", "count":
		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)
		fmt.printfln("Total: %d bangs", len(db.data))
		return

	case "-u", "update", "--update":
		update_kagi_bangs()
		return

	case "completions":
		a = a[1:]
		if len(a) == 0 {
			fmt.eprintln("Expected a shell name")
			return
		}

		switch a[0] {
		case "fish":
			print_fish_completions()
		case:
			fmt.eprintfln("Unsupported shell: %s", a[0])
		}
		return

	case "__complete-bangs":
		prefix := ""
		if len(a) > 1 do prefix = a[1]

		db := Bang_DB{}
		if !load_bang_db(&db) do return
		defer db_destroy(&db)

		print_bang_completions(db.data[:], prefix)
		return

	case:
		fmt.eprintfln("Invalid argument provided: %s", a[0])
		return
	}
}
