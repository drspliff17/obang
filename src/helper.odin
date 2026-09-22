package main

import "core:fmt"
import "core:os"
import "core:strings"

run_command :: proc(command: []string) -> bool {
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)

	defer {
		delete(stdout)
		delete(stderr)
	}

	if err != nil {
		fmt.eprintfln("Failed to start command: %v", err)
		return false
	}

	if !state.exited || state.exit_code != 0 {
		fmt.eprintfln("Command failed (%d): %s", state.exit_code, string(stderr))
		return false
	}

	return true
}

get_path_home :: proc() -> (home_dir: string, ok: bool) {
	h, home_err := os.user_home_dir(context.allocator)
	if home_err != nil {
		fmt.eprintfln("Failed to get home directory: %v", home_err)
		return "", false
	}
	return h, true
}

get_path_cache :: proc(home_dir: string) -> (cache_dir: string, ok: bool) {
	cd, cache_err := os.join_path([]string{home_dir, ".cache", "obang"}, context.allocator)
	if cache_err != nil {
		fmt.eprintfln("Failed to build cache directory path: %v", cache_err)
		return "", false
	}
	return cd, true
}

get_repo_dir :: proc(cache_dir: string) -> (repo_dir: string, ok: bool) {
	r, repo_err := os.join_path([]string{cache_dir, "kagi-bangs"}, context.allocator)
	if repo_err != nil {
		fmt.eprintfln("Failed to build repo path: %v", repo_err)
		return "", false
	}
	return r, true
}

get_source_file :: proc(repo_dir: string) -> (source_file: string, ok: bool) {
	s, source_err := os.join_path([]string{repo_dir, "data", "bangs.json"}, context.allocator)
	if source_err != nil {
		fmt.eprintfln("Failed to build source file path: %v", source_err)
		return "", false
	}
	return s, true
}

get_output_file :: proc(cache_dir: string) -> (output_file: string, ok: bool) {
	o, output_err := os.join_path([]string{cache_dir, "bangs.json"}, context.allocator)
	if output_err != nil {
		fmt.eprintfln("Failed to build output file path: %v", output_err)
		return "", false
	}
	return o, true
}

get_main_paths :: proc() -> (cache_dir, repo_dir, source_file, output_file: string, ok: bool) {
	home_dir, home_ok := get_path_home()
	if !home_ok do return "", "", "", "", false
	defer delete_string(home_dir)

	cd, cache_ok := get_path_cache(home_dir)
	if !cache_ok do return "", "", "", "", false

	r, repo_ok := get_repo_dir(cd)
	if !repo_ok {
		delete_string(cd)
		return "", "", "", "", false
	}

	s, source_ok := get_source_file(r)
	if !source_ok {
		delete_string(cd)
		delete_string(r)
		return "", "", "", "", false
	}

	o, output_ok := get_output_file(cd)
	if !output_ok {
		delete_string(cd)
		delete_string(r)
		delete_string(s)
		return "", "", "", "", false
	}

	return cd, r, s, o, true
}

// Returns a string of all bang names and their triggers, separated by new lines
construct_bang_trigger_list :: proc(bangs: []Bang) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for bang in bangs {
		fmt.sbprintf(&builder, "%s - [%s", bang.name, bang.trigger)
		for alias in bang.triggers {
			fmt.sbprintf(&builder, ", %s", alias)
		}
		fmt.sbprintf(&builder, "]\n")
	}

	return fmt.aprintf("%s", strings.to_string(builder))
}
