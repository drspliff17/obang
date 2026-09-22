package main

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

TERMINAL_SEARCH_LIMIT :: 30

Terminal_Search_Result :: struct {
	index: int,
	score: int,
	name:  string,
}

terminal_query_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

terminal_word_boundary :: proc(c: u8) -> bool {
	return terminal_query_space(c) || c == '-' || c == '_' || c == '/' || c == '.' || c == ':'
}

terminal_fuzzy_name_score :: proc(name, input_query: string) -> int {
	query := strings.trim_space(input_query)
	if len(name) == 0 || len(query) == 0 do return 0

	if strings.equal_fold(name, query) do return 100_000
	if ascii_has_prefix_fold(name, query) do return 90_000 - len(name)
	if ascii_contains_fold(name, query) do return 80_000 - len(name)

	query_index := 0
	last_match := -2
	matched := 0
	score := 0

	for name_index in 0 ..< len(name) {
		for query_index < len(query) && terminal_query_space(query[query_index]) do query_index += 1
		if query_index >= len(query) do break
		if ascii_lower_byte(name[name_index]) != ascii_lower_byte(query[query_index]) do continue

		score += 10

		if name_index == 0 || terminal_word_boundary(name[name_index - 1]) do score += 24
		if name_index == last_match + 1 do score += 18

		last_match = name_index
		matched += 1
		query_index += 1
	}

	for query_index < len(query) && terminal_query_space(query[query_index]) do query_index += 1
	if query_index < len(query) do return 0

	score += matched * 6
	score -= len(name) - matched
	if score < 1 do score = 1

	return score
}

terminal_search_names :: proc(bangs: []Bang, query: string) -> [dynamic]Terminal_Search_Result {
	results := make([dynamic]Terminal_Search_Result, 0, 64)

	for index in 0 ..< len(bangs) {
		score := terminal_fuzzy_name_score(bangs[index].name, query)
		if score == 0 do continue

		append(
			&results,
			Terminal_Search_Result{index = index, score = score, name = bangs[index].name},
		)
	}

	slice.sort_by(results[:], proc(a, b: Terminal_Search_Result) -> bool {
			if a.score != b.score do return a.score > b.score
			return a.name < b.name
		})

	return results
}

print_terminal_bang_row :: proc(bang: ^Bang) {
	fmt.printf("!%s\t%s", bang.trigger, bang.name)

	if len(bang.category) > 0 {
		fmt.printf("\t%s", bang.category)
		if len(bang.subcategory) > 0 do fmt.printf(" > %s", bang.subcategory)
	}
	if len(bang.domain) > 0 do fmt.printf("\t%s", bang.domain)
	fmt.println()
}

terminal_search :: proc(db: ^Bang_DB, query: string) -> bool {
	query := query
	query = strings.trim_space(query)
	if len(query) == 0 {
		fmt.eprintln("Expected a name to search for")
		return false
	}

	results := terminal_search_names(db.data[:], query)
	defer delete(results)

	if len(results) == 0 {
		fmt.eprintfln("No bang names matched: %s", query)
		return false
	}

	count := len(results)
	if count > TERMINAL_SEARCH_LIMIT do count = TERMINAL_SEARCH_LIMIT

	for result in results[:count] do print_terminal_bang_row(&db.data[result.index])
	return true
}

terminal_get_bang :: proc(bangs: []Bang, input_key: string) -> (^Bang, bool) {
	key := strings.trim_space(input_key)
	if len(key) > 0 && key[0] == '!' do key = key[1:]
	if len(key) == 0 do return nil, false

	for index in 0 ..< len(bangs) {
		bang := &bangs[index]

		if strings.equal_fold(bang.trigger, key) do return bang, true
		for alias in bang.triggers do if strings.equal_fold(alias, key) do return bang, true
	}

	return nil, false
}

print_bang_json :: proc(bang: ^Bang) -> bool {
	output, marshal_err := json.marshal(
		bang^,
		json.Marshal_Options{spec = .JSON, pretty = true, use_spaces = true, spaces = 2},
		context.allocator,
	)
	if marshal_err != nil {
		fmt.eprintfln("Failed to encode bang as JSON: %v", marshal_err)
		return false
	}
	defer delete(output)

	fmt.println(string(output))
	return true
}

print_bang_details :: proc(bang: ^Bang) {
	fmt.printfln("Name:        %s", bang.name)
	fmt.printfln("Trigger:     !%s", bang.trigger)

	fmt.print("Aliases:     ")
	if len(bang.triggers) == 0 {
		fmt.println("-")
	} else {
		for alias, index in bang.triggers {
			if index > 0 do fmt.print(", ")
			fmt.printf("!%s", alias)
		}
		fmt.println()
	}

	if len(bang.domain) > 0 {
		fmt.printfln("Domain:      %s", bang.domain)
	} else {
		fmt.println("Domain:      -")
	}

	if len(bang.snap_domain) > 0 {
		fmt.printfln("Snap domain: %s", bang.snap_domain)
	} else {
		fmt.println("Snap domain: -")
	}

	if len(bang.category) > 0 {
		fmt.printfln("Category:    %s", bang.category)
	} else {
		fmt.println("Category:    -")
	}

	if len(bang.subcategory) > 0 {
		fmt.printfln("Subcategory: %s", bang.subcategory)
	} else {
		fmt.println("Subcategory: -")
	}

	fmt.printfln("Template:    %s", bang.template)

	if len(bang.regex_pattern) > 0 {
		fmt.printfln("Regex:       %s", bang.regex_pattern)
	} else {
		fmt.println("Regex:       -")
	}

	fmt.print("Format:      ")
	if bang.format == nil {
		fmt.println("default")
	} else if len(bang.format) == 0 {
		fmt.println("none")
	} else {
		for value, index in bang.format {
			if index > 0 do fmt.print(", ")
			fmt.print(value)
		}
		fmt.println()
	}
}

terminal_get :: proc(db: ^Bang_DB, key: string, json_output: bool = false) -> bool {
	bang, found := terminal_get_bang(db.data[:], key)
	if !found {
		fmt.eprintfln("Bang not found: %s", key)
		return false
	}

	if json_output {
		print_bang_json(bang)
	} else {
		print_bang_details(bang)
	}

	return true
}
