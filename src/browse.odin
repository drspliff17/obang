package main

import "core:fmt"
import "core:slice"
import "core:strings"

// Menu Control
BROWSE_SEARCH_LIMIT :: 60
BROWSE_DIRECT_LIST_LIMIT :: 250

// Static Menu Options
BROWSE_SEARCH_ALL :: "Search bangs"
BROWSE_CATEGORIES :: "Browse categories"
BROWSE_SUBCATEGORIES :: "Browse subcategories"
BROWSE_SEARCH_CATEGORY :: "Search this category"

Category_Row :: struct {
	name:  string,
	count: int,
}

Subcategory_Row :: struct {
	category:    string,
	subcategory: string,
	count:       int,
}

Bang_Row :: struct {
	index:   int,
	name:    string,
	trigger: string,
}

Bang_Search_Result :: struct {
	index: int,
	score: int,
	name:  string,
}

// Convert an ASCII byte to lowercase for simple case-insensitive matching
ascii_lower_byte :: proc(c: u8) -> u8 {
	if c >= 'A' && c <= 'Z' do return c + ('a' - 'A')
	return c
}

// Check whether a string starts with a prefix, ignoring ASCII case
ascii_has_prefix_fold :: proc(value, prefix: string) -> bool {
	if len(prefix) > len(value) do return false
	for i in 0 ..< len(prefix) do if ascii_lower_byte(value[i]) != ascii_lower_byte(prefix[i]) do return false
	return true
}

// Check whether a string contains a substring, ignoring ASCII case
ascii_contains_fold :: proc(value, needle: string) -> bool {
	if len(needle) == 0 do return true
	if len(needle) > len(value) do return false

	last := len(value) - len(needle)
	for offset in 0 ..= last {
		matched := true
		for i in 0 ..< len(needle) {
			if ascii_lower_byte(value[offset + i]) != ascii_lower_byte(needle[i]) {
				matched = false
				break
			}
		}
		if matched do return true
	}
	return false
}

max_int :: proc(a, b: int) -> int {
	if a > b do return a
	return b
}

// Score a field against a search term using exact, prefix and substring matches
score_field :: proc(value, term: string, exact_score, prefix_score, contains_score: int) -> int {
	if len(value) == 0 || len(term) == 0 do return 0
	if strings.equal_fold(value, term) do return exact_score
	if ascii_has_prefix_fold(value, term) do return prefix_score
	if ascii_contains_fold(value, term) do return contains_score
	return 0
}

// Score a search term against the searchable fields of a bang
score_bang_term :: proc(bang: ^Bang, term: string) -> int {
	score := score_field(bang.trigger, term, 120, 105, 85)

	for alias in bang.triggers do score = max_int(score, score_field(alias, term, 115, 100, 80))

	score = max_int(score, score_field(bang.name, term, 100, 90, 75))
	score = max_int(score, score_field(bang.domain, term, 85, 75, 60))
	score = max_int(score, score_field(bang.subcategory, term, 70, 60, 45))
	score = max_int(score, score_field(bang.category, term, 65, 55, 40))

	return score
}

// Score a complete multi-term query against a bang, rewarding exact trigger, alias, name and domain matches
score_bang_search :: proc(bang: ^Bang, input_query: string) -> int {
	query := strings.trim_space(input_query)
	if len(query) == 0 do return 0
	if query[0] == '!' {
		query = strings.trim_space(query[1:])
		if len(query) == 0 do return 0
	}

	rest := query
	total := 0
	term_count := 0

	for {
		term, ok := strings.fields_iterator(&rest)
		if !ok do break

		term_score := score_bang_term(bang, term)
		if term_score == 0 do return 0

		total += term_score
		term_count += 1
	}

	if term_count == 0 do return 0

	if strings.equal_fold(bang.trigger, query) {
		total += 600
	} else {
		for alias in bang.triggers {
			if strings.equal_fold(alias, query) {
				total += 550
				break
			}
		}
	}

	if strings.equal_fold(bang.name, query) do total += 450
	if strings.equal_fold(bang.domain, query) do total += 300

	return total
}

// Return whether a bang belongs to the requested category/subcategory scope
bang_in_scope :: proc(bang: ^Bang, category, subcategory: string) -> bool {
	if len(category) > 0 && bang.category != category do return false
	if len(subcategory) > 0 && bang.subcategory != subcategory do return false
	return true
}

// Search bangs within an optional category/subcategory scope, and return matching results ordered by relevance
search_bangs :: proc(
	bangs: []Bang,
	query: string,
	category: string = "",
	subcategory: string = "",
) -> [dynamic]Bang_Search_Result {
	results := make([dynamic]Bang_Search_Result, 0, 64)

	for index in 0 ..< len(bangs) {
		bang := &bangs[index]
		if !bang_in_scope(bang, category, subcategory) do continue

		score := score_bang_search(bang, query)
		if score == 0 do continue

		append(&results, Bang_Search_Result{index = index, score = score, name = bang.name})
	}

	slice.sort_by(results[:], proc(a, b: Bang_Search_Result) -> bool {
		if a.score != b.score do return a.score > b.score
		return a.name < b.name
	})

	return results
}

// Collect all unique categories, and the number of bangs in each
collect_categories :: proc(bangs: []Bang) -> [dynamic]Category_Row {
	counts := make(map[string]int)
	defer delete(counts)

	for bang in bangs {
		if len(bang.category) == 0 do continue
		count, found := counts[bang.category]
		if found {
			counts[bang.category] = count + 1
		} else {
			counts[bang.category] = 1
		}
	}

	rows := make([dynamic]Category_Row, 0, len(counts))
	for name, count in counts do append(&rows, Category_Row{name = name, count = count})

	slice.sort_by(rows[:], proc(a, b: Category_Row) -> bool {
		return a.name < b.name
	})

	return rows
}

// Collect unique subcategories, optionally restricted to a parent category, together with their bang counts
collect_subcategories :: proc(bangs: []Bang, category: string = "") -> [dynamic]Subcategory_Row {
	rows := make([dynamic]Subcategory_Row, 0, 128)

	for bang in bangs {
		if len(category) > 0 && bang.category != category do continue
		if len(bang.subcategory) == 0 do continue

		found_index := -1
		for row, index in rows {
			if row.category == bang.category && row.subcategory == bang.subcategory {
				found_index = index
				break
			}
		}

		if found_index >= 0 {
			rows[found_index].count += 1
		} else {
			append(
				&rows,
				Subcategory_Row {
					category = bang.category,
					subcategory = bang.subcategory,
					count = 1,
				},
			)
		}
	}

	slice.sort_by(rows[:], proc(a, b: Subcategory_Row) -> bool {
			if a.subcategory != b.subcategory do return a.subcategory < b.subcategory
			return a.category < b.category
		})
	return rows
}

// Collect and sort bang rows within an optional category/subcategory scope
collect_bang_rows :: proc(
	bangs: []Bang,
	category: string = "",
	subcategory: string = "",
) -> [dynamic]Bang_Row {
	rows := make([dynamic]Bang_Row, 0, 64)

	for index in 0 ..< len(bangs) {
		bang := &bangs[index]
		if !bang_in_scope(bang, category, subcategory) do continue
		append(&rows, Bang_Row{index = index, name = bang.name, trigger = bang.trigger})
	}

	slice.sort_by(rows[:], proc(a, b: Bang_Row) -> bool {
		if a.name != b.name do return a.name < b.name
		return a.trigger < b.trigger
	})

	return rows
}

// Append single formatted bang entry to a runner
append_bang_menu_line :: proc(builder: ^strings.Builder, bang: ^Bang) {
	fmt.sbprintf(builder, "!%s\t%s", bang.trigger, bang.name)
	if len(bang.category) > 0 {
		fmt.sbprintf(builder, "\t%s", bang.category)
		if len(bang.subcategory) > 0 do fmt.sbprintf(builder, " > %s", bang.subcategory)
	}

	if len(bang.domain) > 0 do fmt.sbprintf(builder, "\t%s", bang.domain)
	fmt.sbprintf(builder, "\n")
}

// Build runner menu containing category name, and bang counts
construct_category_menu :: proc(rows: []Category_Row) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for row in rows do fmt.sbprintf(&builder, "%s\t%d bangs\n", row.name, row.count)
	return fmt.aprintf("%s", strings.to_string(builder))
}

// Build runner menu containing subcategory name, and bang counts - optionally including the parent category
construct_subcategory_menu :: proc(rows: []Subcategory_Row, include_category: bool) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for row in rows {
		if include_category {
			fmt.sbprintf(&builder, "%s\t%s\t%d bangs\n", row.subcategory, row.category, row.count)
		} else {
			fmt.sbprintf(&builder, "%s\t%d bangs\n", row.subcategory, row.count)
		}
	}

	return fmt.aprintf("%s", strings.to_string(builder))
}

// Build runner menu from a set of bang rows
construct_bang_rows_menu :: proc(bangs: []Bang, rows: []Bang_Row) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for row in rows do append_bang_menu_line(&builder, &bangs[row.index])
	return fmt.aprintf("%s", strings.to_string(builder))
}

// Build runner menu from ranked bang search results
construct_search_menu :: proc(bangs: []Bang, results: []Bang_Search_Result) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for result in results do append_bang_menu_line(&builder, &bangs[result.index])
	return fmt.aprintf("%s", strings.to_string(builder))
}

// Extract and trim the first line returned by a runner
menu_line :: proc(selection: string) -> string {
	line := strings.trim_space(selection)
	if newline := strings.index_byte(line, '\n'); newline >= 0 do line = line[:newline]
	return strings.trim_space(line)
}

// Extract the first tab-separated fields from a runner selection
menu_first_field :: proc(selection: string) -> string {
	line := menu_line(selection)
	if tab := strings.index_byte(line, '\t'); tab >= 0 do return strings.trim_space(line[:tab])
	return line
}

// Extract the first two tab-separated from a runner selection
menu_first_two_fields :: proc(selection: string) -> (first, second: string, ok: bool) {
	line := menu_line(selection)
	first_tab := strings.index_byte(line, '\t')
	if first_tab < 0 do return "", "", false

	first = strings.trim_space(line[:first_tab])
	rest := line[first_tab + 1:]
	second_tab := strings.index_byte(rest, '\t')

	if second_tab < 0 {
		second = strings.trim_space(rest)
	} else {
		second = strings.trim_space(rest[:second_tab])
	}

	if len(first) == 0 || len(second) == 0 do return "", "", false
	return first, second, true
}

// Find a band bt primary trigger, or alias, accepting an optional leading !
find_bang_by_trigger :: proc(bangs: []Bang, trigger_with_bang: string) -> (^Bang, bool) {
	trigger := strings.trim_space(trigger_with_bang)
	if len(trigger) > 0 && trigger[0] == '!' do trigger = trigger[1:]
	if len(trigger) == 0 do return nil, false

	for index in 0 ..< len(bangs) do if bang_matches_trigger(&bangs[index], trigger) do return &bangs[index], true
	return nil, false
}

Browse_Result :: enum {
	Back,
	Done,
	Failed,
}

// Present a bang menu, and resolve the selected entry back into it's Bang
choose_bang_from_menu :: proc(
	bangs: []Bang,
	runner_command: []string,
	menu: string,
) -> (
	^Bang,
	bool,
) {
	selection, selected := get_runner_choice(runner_command, menu)
	if !selected do return nil, false
	defer delete_string(selection)

	trigger := menu_first_field(selection)
	return find_bang_by_trigger(bangs, trigger)
}

// Prompt for a query, resolve the selected bang, and open the resulting URL
// Cancelling returns Back, so the caller can restore the previous menu
run_selected_bang :: proc(bang: ^Bang, runner_command: []string) -> Browse_Result {
	query, accepted := get_runner_input(runner_command)
	if !accepted do return Browse_Result.Back
	defer delete_string(query)

	url, resolved := resolve_bang_target(bang, query)
	if !resolved {
		fmt.eprintfln("Could not resolve !%s", bang.trigger)
		return Browse_Result.Failed
	}
	defer delete_string(url)

	if !open_firefox(url) do return Browse_Result.Failed
	return Browse_Result.Done
}

// Present ranked rearch results and handle navigation between the result list and the
// selected bang's query prompt
browse_search_results :: proc(
	bangs: []Bang,
	runner_command: []string,
	query: string,
	category: string = "",
	subcategory: string = "",
) -> Browse_Result {
	results := search_bangs(bangs, query, category, subcategory)
	defer delete(results)

	if len(results) == 0 {
		fmt.eprintfln("No bangs found for: %s", query)
		return Browse_Result.Back
	}

	result_count := len(results)
	if result_count > BROWSE_SEARCH_LIMIT do result_count = BROWSE_SEARCH_LIMIT

	menu := construct_search_menu(bangs, results[:result_count])
	defer delete_string(menu)

	for {
		bang, selected := choose_bang_from_menu(bangs, runner_command, menu)
		if !selected do return Browse_Result.Back

		result := run_selected_bang(bang, runner_command)
		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return Browse_Result.Done
		case Browse_Result.Failed:
			return Browse_Result.Failed
		}
	}
}

// Prompt for a search query within an optional scope and navigate through it's
// results until user completes action, or goes back
browse_search_scope :: proc(
	bangs: []Bang,
	runner_command: []string,
	category: string = "",
	subcategory: string = "",
) -> Browse_Result {
	for {
		query, entered := get_runner_input(runner_command)
		if !entered do return Browse_Result.Back

		result := browse_search_results(bangs, runner_command, query, category, subcategory)
		delete_string(query)

		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return Browse_Result.Done
		case Browse_Result.Failed:
			return Browse_Result.Failed
		}
	}
}

// Browse bangs within an optional category/subcategory scope, falling back to scoped
// search when the result set is too large for a direct menu
browse_bang_scope :: proc(
	bangs: []Bang,
	runner_command: []string,
	category: string = "",
	subcategory: string = "",
) -> Browse_Result {
	rows := collect_bang_rows(bangs, category, subcategory)
	defer delete(rows)

	if len(rows) == 0 do return Browse_Result.Back
	if len(rows) > BROWSE_DIRECT_LIST_LIMIT do return browse_search_scope(bangs, runner_command, category, subcategory)

	menu := construct_bang_rows_menu(bangs, rows[:])
	defer delete_string(menu)

	for {
		bang, selected := choose_bang_from_menu(bangs, runner_command, menu)
		if !selected do return Browse_Result.Back

		result := run_selected_bang(bang, runner_command)
		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return Browse_Result.Done
		case Browse_Result.Failed:
			return Browse_Result.Failed
		}
	}
}

// Start an unrestricted bang search from the browse interface
browse_search_all :: proc(db: ^Bang_DB, runner_command: []string) -> Browse_Result {
	return browse_search_scope(db.data[:], runner_command)
}

// Browse the subcategories and bangs belonging to a single category
browse_category :: proc(
	db: ^Bang_DB,
	runner_command: []string,
	category: string,
) -> Browse_Result {
	subcategories := collect_subcategories(db.data[:], category)
	defer delete(subcategories)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "%s\n", BROWSE_SEARCH_CATEGORY)

	for row in subcategories do fmt.sbprintf(&builder, "%s\t%d bangs\n", row.subcategory, row.count)

	subcategory_menu := fmt.aprintf("%s", strings.to_string(builder))
	defer delete_string(subcategory_menu)

	for {
		selection, selected := get_runner_choice(runner_command, subcategory_menu)
		if !selected do return Browse_Result.Back

		subcategory := menu_first_field(selection)
		if len(subcategory) == 0 {
			delete_string(selection)
			continue
		}

		result: Browse_Result
		if subcategory == BROWSE_SEARCH_CATEGORY {
			result = browse_search_scope(db.data[:], runner_command, category)
		} else {
			result = browse_bang_scope(db.data[:], runner_command, category, subcategory)
		}
		delete_string(selection)

		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return Browse_Result.Done
		case Browse_Result.Failed:
			return Browse_Result.Failed
		}
	}
}

// Browse all categories and descend into the selected category
browse_categories :: proc(db: ^Bang_DB, runner_command: []string) -> Browse_Result {
	categories := collect_categories(db.data[:])
	defer delete(categories)
	if len(categories) == 0 do return Browse_Result.Back

	category_menu := construct_category_menu(categories[:])
	defer delete_string(category_menu)

	for {
		selection, selected := get_runner_choice(runner_command, category_menu)
		if !selected do return Browse_Result.Back

		category := menu_first_field(selection)
		if len(category) == 0 {
			delete_string(selection)
			continue
		}

		result := browse_category(db, runner_command, category)
		delete_string(selection)

		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return Browse_Result.Done
		case Browse_Result.Failed:
			return Browse_Result.Failed
		}
	}
}

// Browse all category/subcategory pairs and descend into the selected scope
browse_subcategories :: proc(db: ^Bang_DB, runner_command: []string) -> Browse_Result {
	subcategories := collect_subcategories(db.data[:])
	defer delete(subcategories)
	if len(subcategories) == 0 do return Browse_Result.Back

	menu := construct_subcategory_menu(subcategories[:], true)
	defer delete_string(menu)

	for {
		selection, selected := get_runner_choice(runner_command, menu)
		if !selected do return Browse_Result.Back

		subcategory, category, parsed := menu_first_two_fields(selection)
		if !parsed {
			delete_string(selection)
			continue
		}

		result := browse_bang_scope(db.data[:], runner_command, category, subcategory)
		delete_string(selection)

		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return Browse_Result.Done
		case Browse_Result.Failed:
			return Browse_Result.Failed
		}
	}
}

// Run the top-level browse menu and manage navigation until the user completes
// bang action, or closes the root menu
browse_bangs :: proc(db: ^Bang_DB, runner_command: []string) -> bool {
	root_menu :=
		BROWSE_SEARCH_ALL +
		"\tsearch name, trigger, alias, domain or category\n" +
		BROWSE_CATEGORIES +
		"\tcategory > subcategory > bang\n" +
		BROWSE_SUBCATEGORIES +
		"\tsubcategory > bang\n"

	for {
		selection, selected := get_runner_choice(runner_command, root_menu)

		if !selected do return true

		mode := menu_first_field(selection)
		result := Browse_Result.Back
		valid_mode := true

		switch mode {
		case BROWSE_SEARCH_ALL:
			result = browse_search_all(db, runner_command)
		case BROWSE_CATEGORIES:
			result = browse_categories(db, runner_command)
		case BROWSE_SUBCATEGORIES:
			result = browse_subcategories(db, runner_command)
		case:
			valid_mode = false
		}

		delete_string(selection)
		if !valid_mode do continue

		switch result {
		case Browse_Result.Back:
			continue
		case Browse_Result.Done:
			return true
		case Browse_Result.Failed:
			return false
		}
	}
}
