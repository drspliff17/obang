package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

REPO_URL :: "https://github.com/kagisearch/bangs.git"

Bang :: struct {
	name:     string,
	template: string,
	triggers: []string,
}

Kagi_Bang :: struct {
	name:                string `json:"s"`,
	trigger:             string `json:"t"`,
	additional_triggers: []string `json:"ts"`,
	template:            string `json:"u"`,
}

Bang_DB :: struct {
	timestamp: string,
	data:      []Bang,
}

update_kagi_bangs :: proc() -> bool {
	cache_dir, repo_dir, source_file, output_file := get_main_paths()
	defer {
		delete_string(cache_dir)
		delete_string(repo_dir)
		delete_string(source_file)
		delete_string(output_file)
	}

	if !os.exists(cache_dir) {
		make_err := os.make_directory_all(cache_dir)
		if make_err != nil {
			fmt.eprintfln("Failed to create cache directory: %v", make_err)
			return false
		}
	}

	if !os.exists(repo_dir) {
		fmt.println("Cloning bangs ...")
		ok := run_command(
			[]string {
				"git",
				"clone",
				"--depth",
				"1",
				"--branch",
				"main",
				"--single-branch",
				REPO_URL,
				repo_dir,
			},
		)
		if !ok do return false
	} else {
		fmt.println("Updating bangs ...")
		ok := run_command([]string{"git", "-C", repo_dir, "pull", "--ff-only"})
		if !ok do return false
	}

	bang_bytes, read_err := os.read_entire_file(source_file, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read %s: %v", source_file, read_err)
		return false
	}
	defer delete(bang_bytes)

	work_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&work_arena)
	defer mem.dynamic_arena_destroy(&work_arena)

	work_allocator := mem.dynamic_arena_allocator(&work_arena)

	source_bangs: []Kagi_Bang
	json_err := json.unmarshal(bang_bytes, &source_bangs, spec = .JSON, allocator = work_allocator)
	if json_err != nil {
		fmt.eprintfln("Failed to parse Kagi bangs.json: %v", json_err)
		return false
	}

	bangs := make([]Bang, len(source_bangs), work_allocator)
	for source, index in source_bangs {
		triggers := make([]string, 1 + len(source.additional_triggers), work_allocator)
		triggers[0] = source.trigger
		copy(triggers[1:], source.additional_triggers)
		bangs[index] = Bang {
			name     = source.name,
			template = source.template,
			triggers = triggers,
		}
	}

	timestamp, timestamp_ok := time.time_to_rfc3339(time.now(), 0, false)
	if !timestamp_ok {
		fmt.eprintln("Failed to create timestamp")
		return false
	}
	defer delete(timestamp)

	db := Bang_DB {
		timestamp = timestamp,
		data      = bangs,
	}

	output, marshal_err := json.marshal(
		db,
		json.Marshal_Options{spec = .JSON, pretty = true, use_spaces = true, spaces = 2},
		context.allocator,
	)
	if marshal_err != nil {
		fmt.eprintfln("Failed to encode bangs database: %v", marshal_err)
		return false
	}
	defer delete(output)

	write_err := os.write_entire_file(output_file, output)
	if write_err != nil {
		fmt.eprintfln("Failed to write %s: %v", output_file, write_err)
		return false
	}

	fmt.printfln("Updated %s with %d bangs at %s", output_file, len(bangs), timestamp)
	return true
}

load_bang_db :: proc(db: ^Bang_DB) -> bool {
	h, _ := get_path_home()
	c, _ := get_path_cache(h)
	o, _ := get_output_file(c)
	defer {
		delete_string(h)
		delete_string(c)
		delete_string(o)
	}

	if !os.exists(o) do if !update_kagi_bangs() do return false

	bytes, err := os.read_entire_file(o, context.allocator)
	if err != nil {
		fmt.eprintfln("Failed to read %s: %v", o, err)
		return false
	}
	defer delete(bytes)

	e := json.unmarshal(bytes, db)
	if e != nil {
		fmt.eprintfln("Failed to unmarshal data: %v", e)
		return false
	}

	return true
}

resolve_template :: proc(template, query: string) -> string {
	encoded_query := net.percent_encode(query, context.allocator)
	defer delete(encoded_query)

	resolved_url, was_allocated := strings.replace_all(
		template,
		"{{{s}}}",
		encoded_query,
		context.allocator,
	)

	if !was_allocated do return strings.clone(resolved_url, context.allocator)
	return resolved_url
}

resolve_bang :: proc(bangs: []Bang, input_query: string) -> (url: string, found: bool) {
	input := strings.trim_space(input_query)
	if len(input) < 2 || input[0] != '!' do return "", false
	space_index := strings.index_byte(input, ' ')

	trigger: string
	query: string

	if space_index == -1 {
		trigger = input[1:]
	} else {
		trigger = input[1:space_index]
		query = strings.trim_space(input[space_index + 1:])
	}
	if len(trigger) == 0 do return "", false

	for bang in bangs {
		for bang_trigger in bang.triggers {
			if bang_trigger == trigger do return resolve_template(bang.template, query), true
		}
	}

	return "", false
}
