package main

import "core:fmt"
import "core:slice"
import "core:strings"

BROWSE_SEARCH_LIMIT :: 60
BROWSE_DIRECT_LIST_LIMIT :: 250

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

ascii_lower_byte :: proc(c: u8) -> u8 {
	if c >= 'A' && c <= 'Z' do return c + ('a' - 'A')
	return c
}

ascii_has_prefix_fold :: proc(value, prefix: string) -> bool {
	if len(prefix) > len(value) do return false
	for i in 0 ..< len(prefix) do if ascii_lower_byte(value[i]) != ascii_lower_byte(prefix[i]) do return false
	return true
}

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

score_field :: proc(value, term: string, exact_score, prefix_score, contains_score: int) -> int {
	if len(value) == 0 || len(term) == 0 do return 0
	if strings.equal_fold(value, term) do return exact_score
	if ascii_has_prefix_fold(value, term) do return prefix_score
	if ascii_contains_fold(value, term) do return contains_score
	return 0
}

score_bang_term :: proc(bang: ^Bang, term: string) -> int {
	score := score_field(bang.trigger, term, 120, 105, 85)

	for alias in bang.triggers do score = max_int(score, score_field(alias, term, 115, 100, 80))

	score = max_int(score, score_field(bang.name, term, 100, 90, 75))
	score = max_int(score, score_field(bang.domain, term, 85, 75, 60))
	score = max_int(score, score_field(bang.subcategory, term, 70, 60, 45))
	score = max_int(score, score_field(bang.category, term, 65, 55, 40))

	return score
}

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

bang_in_scope :: proc(bang: ^Bang, category, subcategory: string) -> bool {
	if len(category) > 0 && bang.category != category do return false
	if len(subcategory) > 0 && bang.subcategory != subcategory do return false
	return true
}

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

append_bang_menu_line :: proc(builder: ^strings.Builder, bang: ^Bang) {
	fmt.sbprintf(builder, "!%s\t%s", bang.trigger, bang.name)
	if len(bang.category) > 0 {
		fmt.sbprintf(builder, "\t%s", bang.category)
		if len(bang.subcategory) > 0 do fmt.sbprintf(builder, " > %s", bang.subcategory)
	}

	if len(bang.domain) > 0 do fmt.sbprintf(builder, "\t%s", bang.domain)
	fmt.sbprintf(builder, "\n")
}

construct_category_menu :: proc(rows: []Category_Row) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for row in rows do fmt.sbprintf(&builder, "%s\t%d bangs\n", row.name, row.count)
	return fmt.aprintf("%s", strings.to_string(builder))
}

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

construct_bang_rows_menu :: proc(bangs: []Bang, rows: []Bang_Row) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for row in rows do append_bang_menu_line(&builder, &bangs[row.index])
	return fmt.aprintf("%s", strings.to_string(builder))
}

construct_search_menu :: proc(bangs: []Bang, results: []Bang_Search_Result) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for result in results do append_bang_menu_line(&builder, &bangs[result.index])
	return fmt.aprintf("%s", strings.to_string(builder))
}

menu_line :: proc(selection: string) -> string {
	line := strings.trim_space(selection)
	if newline := strings.index_byte(line, '\n'); newline >= 0 do line = line[:newline]
	return strings.trim_space(line)
}

menu_first_field :: proc(selection: string) -> string {
	line := menu_line(selection)
	if tab := strings.index_byte(line, '\t'); tab >= 0 do return strings.trim_space(line[:tab])
	return line
}

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

find_bang_by_trigger :: proc(bangs: []Bang, trigger_with_bang: string) -> (^Bang, bool) {
	trigger := strings.trim_space(trigger_with_bang)
	if len(trigger) > 0 && trigger[0] == '!' do trigger = trigger[1:]
	if len(trigger) == 0 do return nil, false

	for index in 0 ..< len(bangs) do if bang_matches_trigger(&bangs[index], trigger) do return &bangs[index], true
	return nil, false
}

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

run_selected_bang :: proc(bang: ^Bang, runner_command: []string) -> bool {
	query, accepted := get_runner_input(runner_command, true)
	if !accepted do return true
	defer if len(query) > 0 do delete_string(query)

	url, resolved := resolve_bang_target(bang, query)
	if !resolved {
		fmt.eprintfln("Could not resolve !%s", bang.trigger)
		return false
	}
	defer delete_string(url)

	return open_firefox(url)
}

choose_search_result :: proc(
	bangs: []Bang,
	runner_command: []string,
	query: string,
	category: string = "",
	subcategory: string = "",
) -> (
	^Bang,
	bool,
) {
	results := search_bangs(bangs, query, category, subcategory)
	defer delete(results)

	if len(results) == 0 {
		fmt.eprintfln("No bangs found for: %s", query)
		return nil, false
	}

	result_count := len(results)
	if result_count > BROWSE_SEARCH_LIMIT do result_count = BROWSE_SEARCH_LIMIT

	menu := construct_search_menu(bangs, results[:result_count])
	defer delete_string(menu)

	return choose_bang_from_menu(bangs, runner_command, menu)
}

search_scope_and_choose :: proc(
	bangs: []Bang,
	runner_command: []string,
	category: string = "",
	subcategory: string = "",
) -> (
	^Bang,
	bool,
) {
	query, entered := get_runner_input(runner_command)
	if !entered do return nil, false
	defer delete_string(query)

	return choose_search_result(bangs, runner_command, query, category, subcategory)
}

choose_bang_in_scope :: proc(
	bangs: []Bang,
	runner_command: []string,
	category: string = "",
	subcategory: string = "",
) -> (
	^Bang,
	bool,
) {
	rows := collect_bang_rows(bangs, category, subcategory)
	defer delete(rows)

	if len(rows) == 0 do return nil, false
	if len(rows) > BROWSE_DIRECT_LIST_LIMIT do return search_scope_and_choose(bangs, runner_command, category, subcategory)

	menu := construct_bang_rows_menu(bangs, rows[:])
	defer delete_string(menu)

	return choose_bang_from_menu(bangs, runner_command, menu)
}

browse_search_all :: proc(db: ^Bang_DB, runner_command: []string) -> bool {
	bang, selected := search_scope_and_choose(db.data[:], runner_command)
	if !selected do return true
	return run_selected_bang(bang, runner_command)
}

browse_categories :: proc(db: ^Bang_DB, runner_command: []string) -> bool {
	categories := collect_categories(db.data[:])
	defer delete(categories)
	if len(categories) == 0 do return true

	category_menu := construct_category_menu(categories[:])
	defer delete_string(category_menu)

	category_selection, selected := get_runner_choice(runner_command, category_menu)
	if !selected do return true
	defer delete_string(category_selection)

	category := menu_first_field(category_selection)
	if len(category) == 0 do return true

	subcategories := collect_subcategories(db.data[:], category)
	defer delete(subcategories)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "%s\n", BROWSE_SEARCH_CATEGORY)

	for row in subcategories do fmt.sbprintf(&builder, "%s\t%d bangs\n", row.subcategory, row.count)

	subcategory_menu := fmt.aprintf("%s", strings.to_string(builder))
	defer delete_string(subcategory_menu)

	subcategory_selection, sub_selected := get_runner_choice(runner_command, subcategory_menu)
	if !sub_selected do return true
	defer delete_string(subcategory_selection)

	subcategory := menu_first_field(subcategory_selection)
	if subcategory == BROWSE_SEARCH_CATEGORY {
		bang, found := search_scope_and_choose(db.data[:], runner_command, category)
		if !found do return true
		return run_selected_bang(bang, runner_command)
	}

	bang, found := choose_bang_in_scope(db.data[:], runner_command, category, subcategory)
	if !found do return true

	return run_selected_bang(bang, runner_command)
}

browse_subcategories :: proc(db: ^Bang_DB, runner_command: []string) -> bool {
	subcategories := collect_subcategories(db.data[:])
	defer delete(subcategories)
	if len(subcategories) == 0 do return true

	menu := construct_subcategory_menu(subcategories[:], true)
	defer delete_string(menu)

	selection, selected := get_runner_choice(runner_command, menu)
	if !selected do return true
	defer delete_string(selection)

	subcategory, category, parsed := menu_first_two_fields(selection)
	if !parsed do return true

	bang, found := choose_bang_in_scope(db.data[:], runner_command, category, subcategory)
	if !found do return true

	return run_selected_bang(bang, runner_command)
}

browse_bangs :: proc(db: ^Bang_DB, runner_command: []string) -> bool {
	root_menu :=
		BROWSE_SEARCH_ALL +
		"\tsearch name, trigger, alias, domain or category\n" +
		BROWSE_CATEGORIES +
		"\tcategory > subcategory > bang\n" +
		BROWSE_SUBCATEGORIES +
		"\tsubcategory > bang\n"

	selection, selected := get_runner_choice(runner_command, root_menu)
	if !selected do return true
	defer delete_string(selection)

	mode := menu_first_field(selection)
	switch mode {
	case BROWSE_SEARCH_ALL:
		return browse_search_all(db, runner_command)
	case BROWSE_CATEGORIES:
		return browse_categories(db, runner_command)
	case BROWSE_SUBCATEGORIES:
		return browse_subcategories(db, runner_command)
	}

	return true
}
