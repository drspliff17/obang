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

// Deep-clone a string slice for independent ownership
clone_string_slice :: proc(values: []string) -> []string {
	if values == nil do return nil

	result := make([]string, len(values))
	for value, index in values do result[index] = strings.clone(value)
	return result
}

// Deep-clone a bang so the returned value owns all of its strings and slices
bang_clone :: proc(source: ^Bang) -> Bang {
	result := Bang{}

	if len(source.name) > 0 do result.name = strings.clone(source.name)
	if len(source.domain) > 0 do result.domain = strings.clone(source.domain)
	if len(source.snap_domain) > 0 do result.snap_domain = strings.clone(source.snap_domain)
	if len(source.trigger) > 0 do result.trigger = strings.clone(source.trigger)
	if len(source.template) > 0 do result.template = strings.clone(source.template)
	if len(source.regex_pattern) > 0 do result.regex_pattern = strings.clone(source.regex_pattern)
	if len(source.category) > 0 do result.category = strings.clone(source.category)
	if len(source.subcategory) > 0 do result.subcategory = strings.clone(source.subcategory)

	result.triggers = clone_string_slice(source.triggers)
	result.format = clone_string_slice(source.format)
	return result
}

// Return whether a custom bang's primary trigger matches an existing bang's
// primary trigger or one of its aliases. Custom aliases do not select the
// override target - they are claimed separately during the merge
bang_matches_custom_trigger :: proc(bang, custom: ^Bang) -> bool {
	if strings.equal_fold(bang.trigger, custom.trigger) do return true
	for alias in bang.triggers do if strings.equal_fold(alias, custom.trigger) do return true
	return false
}

// Find the loaded bang that a config bang should override. Name matches take
// precedence, followed by a match against the custom bang's primary trigger
find_bang_override_index :: proc(bangs: []Bang, custom: ^Bang) -> int {
	for bang, index in bangs do if strings.equal_fold(bang.name, custom.name) do return index
	for _, index in bangs do if bang_matches_custom_trigger(&bangs[index], custom) do return index
	return -1
}

// Overlay the fields supplied by a config bang onto an existing loaded bang
// Required fields always replace. Optional strings inherit when empty, while
// nil slices inherit and explicitly present empty slices replace
bang_apply_override :: proc(target, custom: ^Bang) {
	if len(target.name) > 0 do delete_string(target.name)
	target.name = strings.clone(custom.name)

	if len(target.trigger) > 0 do delete_string(target.trigger)
	target.trigger = strings.clone(custom.trigger)

	if len(target.template) > 0 do delete_string(target.template)
	target.template = strings.clone(custom.template)

	if len(custom.domain) > 0 {
		if len(target.domain) > 0 do delete_string(target.domain)
		target.domain = strings.clone(custom.domain)
	}

	if len(custom.snap_domain) > 0 {
		if len(target.snap_domain) > 0 do delete_string(target.snap_domain)
		target.snap_domain = strings.clone(custom.snap_domain)
	}

	if len(custom.regex_pattern) > 0 {
		if len(target.regex_pattern) > 0 do delete_string(target.regex_pattern)
		target.regex_pattern = strings.clone(custom.regex_pattern)
	}

	if len(custom.category) > 0 {
		if len(target.category) > 0 do delete_string(target.category)
		target.category = strings.clone(custom.category)
	}

	if len(custom.subcategory) > 0 {
		if len(target.subcategory) > 0 do delete_string(target.subcategory)
		target.subcategory = strings.clone(custom.subcategory)
	}

	if custom.triggers != nil {
		for value in target.triggers do delete_string(value)
		delete(target.triggers)
		target.triggers = clone_string_slice(custom.triggers)
	}

	if custom.format != nil {
		for value in target.format do delete_string(value)
		delete(target.format)
		target.format = clone_string_slice(custom.format)
	}
}

// Remove an alias from a bang while preserving ownership of all aliases that
// remain. Every matching occurrence is removed
bang_remove_alias :: proc(bang: ^Bang, alias: string) {
	remove_count := 0
	for value in bang.triggers do if strings.equal_fold(value, alias) do remove_count += 1
	if remove_count == 0 do return

	remaining := len(bang.triggers) - remove_count
	new_triggers: []string
	if remaining > 0 do new_triggers = make([]string, remaining)

	write_index := 0
	for value in bang.triggers {
		if strings.equal_fold(value, alias) {
			delete_string(value)
			continue
		}

		new_triggers[write_index] = value
		write_index += 1
	}

	delete(bang.triggers)
	bang.triggers = new_triggers
}

// Remove the custom bang's claimed trigger and aliases from every other bang's
// alias list. This keeps the trigger namespace unambiguous without deleting or
// rewriting another bang's primary trigger
db_claim_custom_keys :: proc(db: ^Bang_DB, owner_index: int, custom: ^Bang) {
	for index in 0 ..< len(db.data) {
		if index == owner_index do continue

		other := &db.data[index]
		bang_remove_alias(other, custom.trigger)
		for alias in custom.triggers do bang_remove_alias(other, alias)
	}
}

// Append a deep-cloned bang to the loaded database and return its new index
db_append_bang_clone :: proc(db: ^Bang_DB, source: ^Bang) -> int {
	old_data := db.data
	new_index := len(old_data)
	new_data := make([]Bang, new_index + 1)

	for bang, index in old_data do new_data[index] = bang
	new_data[new_index] = bang_clone(source)

	delete(old_data)
	db.data = new_data
	return new_index
}

// Merge config bangs over the loaded Kagi database. A matching name or primary
// trigger overrides the existing bang. Unique custom bangs are appended. After
// each merge, the custom bang claims its configured trigger/aliases by removing
// those values from every other bang's alias list
merge_custom_bangs :: proc(db: ^Bang_DB, custom_bangs: []Bang) {
	for &custom in custom_bangs {
		index := find_bang_override_index(db.data[:], &custom)
		if index >= 0 {
			bang_apply_override(&db.data[index], &custom)
		} else {
			index = db_append_bang_clone(db, &custom)
		}

		db_claim_custom_keys(db, index, &custom)
	}
}

// Free all heap-owned fields within given bang
bang_free :: proc(b: ^Bang) {
	if len(b.name) > 0 do delete_string(b.name)
	if len(b.template) > 0 do delete_string(b.template)
	if len(b.trigger) > 0 do delete_string(b.trigger)
	if len(b.snap_domain) > 0 do delete_string(b.snap_domain)
	if len(b.category) > 0 do delete_string(b.category)
	if len(b.domain) > 0 do delete_string(b.domain)
	if len(b.regex_pattern) > 0 do delete_string(b.regex_pattern)
	if len(b.subcategory) > 0 do delete_string(b.subcategory)

	for x in b.triggers do delete_string(x)
	delete(b.triggers)

	for x in b.format do delete_string(x)
	delete(b.format)
}

// Free all heap-owned data in a loaded bang database
db_destroy :: proc(db: ^Bang_DB) {
	if len(db.timestamp) > 0 do delete_string(db.timestamp)
	for &b in db.data do bang_free(&b)
	delete(db.data)
}

// Clone or update the Kagi bangs repository, normalize it's bang data,
// and rebuild the local json cache
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

// Merge external custom bang files in config order. Later files override earlier
// files, and inline config.custom.bangs are merged separately afterwards
merge_custom_bang_files :: proc(db: ^Bang_DB, config: ^Config) -> bool {
	if len(config.files) == 0 do return true

	home_dir, home_ok := get_path_home()
	if !home_ok do return false
	defer delete_string(home_dir)

	config_file, config_ok := get_config_file(home_dir)
	if !config_ok do return false
	defer delete_string(config_file)

	for path in config.files {
		bangs, loaded := config_load_bang_file(path, config_file)
		if !loaded do return false

		merge_custom_bangs(db, bangs)
		config_destroy_bang_slice(bangs)
	}

	return true
}

// Load the cached bang database, rebuilding it when the cache schema version no longer matches current schema (or is missing)
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

	if !os.exists(output_file) {
		if !update_kagi_bangs() do return false
	}

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

	config := cast(^Config)context.user_ptr
	if config != nil {
		// External files are merged in listed order first.
		if !merge_custom_bang_files(db, config) {
			db_destroy(db)
			return false
		}

		// Inline config bangs always merge last and are the final authority.
		if len(config.bangs) > 0 do merge_custom_bangs(db, config.bangs)
	}

	return true
}

// Return whether a bang supports a given format flag
bang_has_format :: proc(bang: ^Bang, flag: string) -> bool {
	if bang.format == nil do return true
	for value in bang.format do if value == flag do return true
	return false
}

// Return whether a trigger matches either the bang's primary trigger, or one of it's aliases
bang_matches_trigger :: proc(bang: ^Bang, trigger: string) -> bool {
	if bang.trigger == trigger do return true
	for alias in bang.triggers do if alias == trigger do return true
	return false
}

// Replace all occurences in an owned string, while preserving ownership of the returned
// value, and freeing the previous allocation when replacement occurs
replace_owned :: proc(value, old, new: string) -> string {
	replaced, allocated := strings.replace_all(value, old, new, context.allocator)
	if allocated {
		delete_string(value)
		return replaced
	}
	return value
}

// Encode query for {{{s}}} placeholder, accordsing to bang's format flags
// Including optional space-to-plus conversion
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

// Find the highest numbered $N placeholder present in template
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

// Replace ordinary $N placeholders using whitespace-separated query parts, with the
// final placeholder receiving the remaining query text
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

// Match a query against a bang regex and replace $N placeholders with the
// corresponding capture groups
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
	if !matched do return "", false
	defer regex.destroy_capture(capture)

	result := fmt.aprintf("%s", template)

	// groups[0] is the full match. $1 starts at groups[1]
	for index := len(capture.groups) - 1; index >= 1; index -= 1 {
		marker := fmt.aprintf("$%d", index)
		result = replace_owned(result, marker, capture.groups[index])
		delete_string(marker)
	}

	return result, true
}

// Convert protocol-relative or domain-relative resolved url into absolute url
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

// Resolve a query against a single bang, applying regex/default placeholders, query encoding rules,
// empty query behaviour, and url finalization
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

// Resolve a simple {{{s}}} search template using percent-encoding, with spaces converted to +
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

// Parse a full bang query, find the matching bang by trigger, or alias, and resolve it to it's final url
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
