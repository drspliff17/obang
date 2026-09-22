package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

main :: proc() {

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("%v allocations not feed:\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		} else {
			fmt.println("TEST: No unfreed allocations")
		}

		if len(track.bad_free_array) > 0 {
			fmt.eprintf("%v incorrect free:\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %v bytes @ %v\n", entry.memory, entry.location)
			}
		} else {
			fmt.println("TEST: No bad free")
		}

		mem.tracking_allocator_destroy(&track)
	}
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
			fmt.eprintfln("Could not resolve runner output: %s", runner_input)
			return
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

	case "test":
		db := Bang_DB{}
		if !load_bang_db(&db) do return
		fmt.printfln("Loaded %d bangs", len(db.data))
		return

	case "-u", "update", "--update":
		update_kagi_bangs()
		return

	case:
		fmt.eprintfln("Invalid argument provided: %s", a[0])
		return
	}

}
