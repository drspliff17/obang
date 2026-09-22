package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:strings"
import "core:text/regex"
import "core:time"

REPO_URL :: "https://github.com/kagisearch/bangs.git"
BANG_DB_SCHEMA_VERSION :: 2

Bang :: struct {
	name:          string,
	domain:        string,
	snap_domain:   string,
	trigger:       string,
	triggers:      []string,
	template:      string,
	regex_pattern: string,
	category:      string,
	subcategory:   string,
	format:        []string,
}

Kagi_Bang :: struct {
	name:                string `json:"s"`,
	domain:              string `json:"d"`,
	snap_domain:         string `json:"ad"`,
	trigger:             string `json:"t"`,
	additional_triggers: []string `json:"ts"`,
	template:            string `json:"u"`,
	regex_pattern:       string `json:"x"`,
	category:            string `json:"c"`,
	subcategory:         string `json:"sc"`,
	format:              []string `json:"fmt"`,
}

Bang_DB :: struct {
	schema_version: int,
	timestamp:      string,
	data:           []Bang,
}

Bang_DB_Header :: struct {
	schema_version: int,
}

update_kagi_bangs :: proc() -> bool {
	cache_dir, repo_dir, source_file, output_file, paths_ok := get_main_paths()
	if !paths_ok do return false
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
		bangs[index] = Bang {
			name          = source.name,
			domain        = source.domain,
			snap_domain   = source.snap_domain,
			trigger       = source.trigger,
			triggers      = source.additional_triggers,
			template      = source.template,
			regex_pattern = source.regex_pattern,
			category      = source.category,
			subcategory   = source.subcategory,
			format        = source.format,
		}
	}

	timestamp, timestamp_ok := time.time_to_rfc3339(time.now(), 0, false)
	if !timestamp_ok {
		fmt.eprintln("Failed to create timestamp")
		return false
	}
	defer delete(timestamp)

	db := Bang_DB {
		schema_version = BANG_DB_SCHEMA_VERSION,
		timestamp      = timestamp,
		data           = bangs,
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
	home_dir, home_ok := get_path_home()
	if !home_ok do return false
	defer delete_string(home_dir)

	cache_dir, cache_ok := get_path_cache(home_dir)
	if !cache_ok do return false
	defer delete_string(cache_dir)

	output_file, output_ok := get_output_file(cache_dir)
	if !output_ok do return false
	defer delete_string(output_file)

	if !os.exists(output_file) do if !update_kagi_bangs() do return false

	bytes, read_err := os.read_entire_file(output_file, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read %s: %v", output_file, read_err)
		return false
	}
	defer delete(bytes)

	header := Bang_DB_Header{}
	header_err := json.unmarshal(bytes, &header)
	if header_err != nil {
		fmt.eprintfln("Failed to read database header: %v", header_err)
		return false
	}

	if header.schema_version != BANG_DB_SCHEMA_VERSION {
		fmt.println("Bang database schema changed; rebuilding cache ...")
		if !update_kagi_bangs() do return false
		return load_bang_db(db)
	}

	unmarshal_err := json.unmarshal(bytes, db)
	if unmarshal_err != nil {
		fmt.eprintfln("Failed to unmarshal data: %v", unmarshal_err)
		return false
	}

	return true
}

bang_has_format :: proc(bang: ^Bang, flag: string) -> bool {
	// Kagi's default is all format flags enabled when fmt is absent
	if bang.format == nil do return true
	for value in bang.format do if value == flag do return true
	return false
}

bang_matches_trigger :: proc(bang: ^Bang, trigger: string) -> bool {
	if bang.trigger == trigger do return true
	for alias in bang.triggers do if alias == trigger do return true
	return false
}

replace_owned :: proc(value, old, new: string) -> string {
	replaced, allocated := strings.replace_all(value, old, new, context.allocator)
	if allocated {
		delete_string(value)
		return replaced
	}
	return value
}

encode_query_placeholder :: proc(bang: ^Bang, query: string) -> string {
	if !bang_has_format(bang, "url_encode_placeholder") do return fmt.aprintf("%s", query)

	encoded := net.percent_encode(query, context.allocator)
	if !bang_has_format(bang, "url_encode_space_to_plus") do return encoded

	with_pluses, allocated := strings.replace_all(encoded, "%20", "+", context.allocator)
	if allocated {
		delete_string(encoded)
		return with_pluses
	}

	return encoded
}

highest_dollar_placeholder :: proc(template: string) -> int {
	highest := 0
	i := 0

	for i < len(template) {
		if template[i] != '$' {
			i += 1
			continue
		}

		j := i + 1
		value := 0
		has_digit := false

		for j < len(template) && template[j] >= '0' && template[j] <= '9' {
			has_digit = true
			value = value * 10 + int(template[j] - '0')
			j += 1
		}

		if has_digit && value > highest do highest = value
		if has_digit {
			i = j
		} else {
			i += 1
		}
	}

	return highest
}

replace_default_dollar_placeholders :: proc(template, query: string) -> string {
	result := fmt.aprintf("%s", template)
	placeholder_count := highest_dollar_placeholder(template)
	if placeholder_count == 0 do return result

	parts := make([]string, placeholder_count)
	defer delete(parts)

	rest := strings.trim_space(query)
	for index in 0 ..< placeholder_count {
		if index == placeholder_count - 1 {
			parts[index] = rest
			break
		}

		part, ok := strings.fields_iterator(&rest)
		if !ok do break
		parts[index] = part
	}

	for index := placeholder_count; index >= 1; index -= 1 {
		marker := fmt.aprintf("$%d", index)
		result = replace_owned(result, marker, parts[index - 1])
		delete_string(marker)
	}

	return result
}

replace_regex_dollar_placeholders :: proc(
	template, query, pattern: string,
) -> (
	url: string,
	ok: bool,
) {
	compiled, compile_err := regex.create(pattern, {.Unicode})
	if compile_err != nil {
		fmt.eprintfln("Failed to compile bang regex %q: %v", pattern, compile_err)
		return "", false
	}
	defer regex.destroy_regex(compiled)

	capture, matched := regex.match_and_allocate_capture(compiled, query)
	if !matched {
		return "", false
	}
	defer regex.destroy_capture(capture)

	result := fmt.aprintf("%s", template)

	// groups[0] is the full match. $1 starts at groups[1].
	for index := len(capture.groups) - 1; index >= 1; index -= 1 {
		marker := fmt.aprintf("$%d", index)
		result = replace_owned(result, marker, capture.groups[index])
		delete_string(marker)
	}

	return result, true
}

finalize_bang_url :: proc(bang: ^Bang, url: string) -> string {
	if strings.has_prefix(url, "//") {
		absolute := fmt.aprintf("https:%s", url)
		delete_string(url)
		return absolute
	}

	if strings.has_prefix(url, "/") {
		absolute := fmt.aprintf("https://%s%s", bang.domain, url)
		delete_string(url)
		return absolute
	}

	return url
}

resolve_bang_target :: proc(bang: ^Bang, input_query: string) -> (url: string, ok: bool) {
	query := strings.trim_space(input_query)

	if len(query) == 0 {
		if bang_has_format(bang, "open_snap_domain") && len(bang.snap_domain) > 0 do return fmt.aprintf("https://%s", bang.snap_domain), true
		if bang_has_format(bang, "open_base_path") do return fmt.aprintf("https://%s/", bang.domain), true
	}

	resolved: string

	if len(bang.regex_pattern) > 0 {
		regex_url, regex_ok := replace_regex_dollar_placeholders(
			bang.template,
			query,
			bang.regex_pattern,
		)
		if !regex_ok do return "", false
		resolved = regex_url
	} else {
		resolved = replace_default_dollar_placeholders(bang.template, query)
	}

	encoded_query := encode_query_placeholder(bang, query)
	resolved = replace_owned(resolved, "{{{s}}}", encoded_query)
	delete_string(encoded_query)

	return finalize_bang_url(bang, resolved), true
}

resolve_template :: proc(template, query: string) -> string {
	encoded_query := net.percent_encode(query, context.allocator)
	with_pluses, allocated := strings.replace_all(encoded_query, "%20", "+", context.allocator)
	if allocated {
		delete_string(encoded_query)
		encoded_query = with_pluses
	}
	defer delete_string(encoded_query)

	result := fmt.aprintf("%s", template)
	return replace_owned(result, "{{{s}}}", encoded_query)
}

resolve_bang :: proc(bangs: []Bang, input_query: string) -> (url: string, found: bool) {
	input := strings.trim_space(input_query)
	if len(input) < 2 || input[0] != '!' do return "", false

	bang_token, token_ok := strings.fields_iterator(&input)
	if !token_ok || len(bang_token) < 2 do return "", false

	trigger := bang_token[1:]
	query := strings.trim_space(input)
	if len(trigger) == 0 do return "", false

	for &bang in bangs {
		if !bang_matches_trigger(&bang, trigger) do continue
		return resolve_bang_target(&bang, query)
	}

	return "", false
}
