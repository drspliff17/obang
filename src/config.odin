package main

import "core:encoding/json"
import "core:fmt"
import "core:os"

Config_General :: struct {
	browser_cmd_prefix:  string,
	browser_win_prefix:  string,
	browser_tab_prefix:  string,
	default_bounce_bang: string,
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

config_verify :: proc(c: ^Config) -> bool {
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

	for x in c.bangs {

		//TODO: Add proper Bang Verification here

		if len(x.name) == 0 {
			fmt.println("[ERROR] Custom bang is missing name")
			return false
		}

		if len(x.template) == 0 {
			fmt.println("[ERROR] Custom bang is missing template")
			return false
		}

		if len(x.trigger) == 0 {
			fmt.println("[ERROR] Custom bang is missing trigger")
			return false
		}
	}

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
	return config_verify(c)
}

config_destroy :: proc(c: ^Config) {
	if len(c.browser_cmd_prefix) > 0 do delete_string(c.browser_cmd_prefix)
	if len(c.browser_tab_prefix) > 0 do delete_string(c.browser_tab_prefix)
	if len(c.browser_win_prefix) > 0 do delete_string(c.browser_win_prefix)

	if len(c.default_bounce_bang) > 0 do delete_string(c.default_bounce_bang)

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
