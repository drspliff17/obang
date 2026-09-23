package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Config_General :: struct {
	browser_cmd_prefix:  string,
	browser_win_prefix:  string,
	browser_tab_prefix:  string,
	default_bounce_bang: string,
	alternate_prefix:    string,
	allow_notifications: bool,
	lazy_bangs:          bool,
}

Config_Runner :: struct {
	empty_runner_cmd:              []string,
	browse_root_runner_cmd:        []string,
	browse_bang_runner_cmd:        []string,
	browse_category_runner_cmd:    []string,
	browse_subcategory_runner_cmd: []string,
}

Config_Bangs :: struct {
	files: []string,
	bangs: []Bang,
}

Config :: struct {
	using custom:           Config_Bangs,
	using runner_settings:  Config_Runner,
	using general_settings: Config_General,
}

config_create_default :: proc(filepath: string) {
	default_config := Config {
		general_settings = {
			browser_cmd_prefix = "firefox",
			browser_tab_prefix = "--new-tab",
			browser_win_prefix = "--new-window",
			default_bounce_bang = "!google",
			alternate_prefix = "",
		},
		runner_settings = {
			empty_runner_cmd = {"wofi", "-d", "-W", "25%", "-H", "10%"},
			browse_root_runner_cmd = {"wofi", "-d", "-p", "obang", "-d", "-W", "30%", "-L", "3"},
			browse_bang_runner_cmd = {"wofi", "-d", "-p", "pick bang", "-W", "45%", "-H", "30%"},
			browse_category_runner_cmd = {
				"wofi",
				"-d",
				"-p",
				"pick category",
				"-W",
				"30%",
				"-H",
				"30%",
			},
			browse_subcategory_runner_cmd = {
				"wofi",
				"-d",
				"-p",
				"pick subcategory",
				"-W",
				"30%",
				"-H",
				"30%",
			},
		},
	}

	if !os.exists(os.dir(filepath)) do if e := os.make_directory_all(os.dir(filepath)); e != nil do fmt.panicf("Failed to create config directory: %v", e)

	bytes, err := json.marshal(default_config)
	if err != nil do fmt.panicf("Failed to marshal default options: %v", err)
	defer delete(bytes)

	if e := os.write_entire_file_from_bytes(filepath, bytes); e != nil do fmt.panicf("Failed to write default config: %v", e)
}

config_load :: proc(c: ^Config, filepath: string) {
	bytes, err := os.read_entire_file(filepath, context.allocator)
	if err != nil do fmt.panicf("Failed to read config file: %v", err)
	defer delete(bytes)

	if e := json.unmarshal(bytes, c); e != nil do fmt.panicf("Failed to unmarshal config: %v", e)
}

// Verify required fields for a custom bang source.
config_verify_bangs :: proc(bangs: []Bang, source: string) -> bool {
	for x, index in bangs {
		if len(x.name) == 0 {
			fmt.eprintfln("[ERROR] %s: bang %d is missing 'name'", source, index + 1)
			return false
		}

		if len(x.template) == 0 {
			fmt.eprintfln("[ERROR] %s: bang %d is missing 'template'", source, index + 1)
			return false
		}

		if len(x.trigger) == 0 {
			fmt.eprintfln("[ERROR] %s: bang %d is missing 'trigger'", source, index + 1)
			return false
		}
	}

	return true
}

// Free a temporary slice of custom bangs loaded from an external file.
config_destroy_bang_slice :: proc(bangs: []Bang) {
	for &bang in bangs do bang_free(&bang)
	delete(bangs)
}

// Resolve a custom bang filepath. Absolute paths are used as-is, ~/ paths are
// expanded from the user's home directory, and relative paths are resolved
// relative to the directory containing config.json.
config_resolve_bang_file_path :: proc(
	path, config_filepath: string,
) -> (
	resolved_path: string,
	ok: bool,
) {
	trimmed := strings.trim_space(path)
	if len(trimmed) == 0 {
		fmt.eprintln("[ERROR] custom.files contains an empty filepath")
		return "", false
	}

	if trimmed[0] == '/' do return strings.clone(trimmed), true

	if trimmed == "~" || strings.has_prefix(trimmed, "~/") {
		home, home_ok := get_path_home()
		if !home_ok do return "", false
		defer delete_string(home)

		if trimmed == "~" do return strings.clone(home), true

		resolved, join_err := os.join_path([]string{home, trimmed[2:]}, context.allocator)
		if join_err != nil {
			fmt.eprintfln("[ERROR] Failed to resolve custom bang file %s: %v", path, join_err)
			return "", false
		}
		return resolved, true
	}

	resolved, join_err := os.join_path(
		[]string{os.dir(config_filepath), trimmed},
		context.allocator,
	)
	if join_err != nil {
		fmt.eprintfln("[ERROR] Failed to resolve custom bang file %s: %v", path, join_err)
		return "", false
	}
	return resolved, true
}

// Load and validate a JSON file containing a plain array of Bang objects
// Ownership of the returned bangs belongs to the caller
config_load_bang_file :: proc(path, config_filepath: string) -> (bangs: []Bang, ok: bool) {
	resolved, path_ok := config_resolve_bang_file_path(path, config_filepath)
	if !path_ok do return nil, false
	defer delete_string(resolved)

	if !os.exists(resolved) {
		fmt.eprintfln("[ERROR] Custom bang file does not exist: %s", resolved)
		return nil, false
	}

	bytes, read_err := os.read_entire_file(resolved, context.allocator)
	if read_err != nil {
		fmt.eprintfln("[ERROR] Failed to read custom bang file %s: %v", resolved, read_err)
		return nil, false
	}
	defer delete(bytes)

	unmarshal_err := json.unmarshal(bytes, &bangs)
	if unmarshal_err != nil {
		if bangs != nil do config_destroy_bang_slice(bangs)
		fmt.eprintfln("[ERROR] Failed to parse custom bang file %s: %v", resolved, unmarshal_err)
		return nil, false
	}

	if !config_verify_bangs(bangs, resolved) {
		config_destroy_bang_slice(bangs)
		return nil, false
	}

	return bangs, true
}

config_verify :: proc(c: ^Config, filepath: string) -> bool {
	if len(c.browser_cmd_prefix) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browser_cmd_prefix'")
		return false
	}

	if len(c.browser_tab_prefix) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browser_tab_prefix'")
		return false
	}

	if len(c.browser_win_prefix) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browser_win_prefix'")
		return false
	}

	if len(c.browse_root_runner_cmd) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browse_root_runner_cmd'")
		return false
	}

	if len(c.browse_bang_runner_cmd) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browse_bang_runner_cmd'")
		return false
	}

	if len(c.browse_category_runner_cmd) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browse_category_runner_cmd'")
		return false
	}

	if len(c.browse_subcategory_runner_cmd) == 0 {
		fmt.eprintln("[ERROR] Config missing 'browse_subcategory_runner_cmd'")
		return false
	}

	if len(c.empty_runner_cmd) == 0 {
		fmt.eprintln("[ERROR] Config missing 'empty_runner_cmd'")
		return false
	}

	for path in c.files {
		bangs, loaded := config_load_bang_file(path, filepath)
		if !loaded do return false
		config_destroy_bang_slice(bangs)
	}

	if !config_verify_bangs(c.bangs, "config.custom.bangs") do return false

	return true
}

config_init :: proc(c: ^Config) -> bool {
	h, _ := get_path_home()
	cfg_path, _ := get_config_file(h)
	defer {
		delete_string(h)
		delete_string(cfg_path)
	}
	if !os.exists(cfg_path) do config_create_default(cfg_path)
	config_load(c, cfg_path)

	if !config_verify(c, cfg_path) {
		config_destroy(c)
		return false
	}

	return true
}

config_destroy :: proc(c: ^Config) {
	if len(c.browser_cmd_prefix) > 0 do delete_string(c.browser_cmd_prefix)
	if len(c.browser_tab_prefix) > 0 do delete_string(c.browser_tab_prefix)
	if len(c.browser_win_prefix) > 0 do delete_string(c.browser_win_prefix)

	if len(c.default_bounce_bang) > 0 do delete_string(c.default_bounce_bang)
	if len(c.alternate_prefix) > 0 do delete_string(c.alternate_prefix)

	for path in c.files do delete_string(path)
	delete(c.files)

	for &x in c.bangs do bang_free(&x)
	delete(c.bangs)

	for x in c.browse_root_runner_cmd do delete_string(x)
	delete(c.browse_root_runner_cmd)

	for x in c.browse_bang_runner_cmd do delete_string(x)
	delete(c.browse_bang_runner_cmd)

	for x in c.browse_category_runner_cmd do delete_string(x)
	delete(c.browse_category_runner_cmd)

	for x in c.browse_subcategory_runner_cmd do delete_string(x)
	delete(c.browse_subcategory_runner_cmd)

	for x in c.empty_runner_cmd do delete_string(x)
	delete(c.empty_runner_cmd)
}
