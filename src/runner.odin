package main

import "core:fmt"
import "core:os"
import "core:strings"

get_runner_input :: proc(command: []string) -> (output: string, ok: bool) {
	stdin_read, stdin_write, pipe_err := os.pipe()
	if pipe_err != nil {
		fmt.eprintfln("Failed to create stdin pipe: %v", pipe_err)
		return "", false
	}

	os.close(stdin_write)
	defer os.close(stdin_read)

	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = command, stdin = stdin_read},
		context.allocator,
	)

	defer {
		delete(stdout)
		delete(stderr)
	}

	if exec_err != nil {
		fmt.eprintfln("Failed to start runner: %v", exec_err)
		return "", false
	}

	if !state.exited || state.exit_code != 0 {
		if len(stderr) > 0 do fmt.eprintfln("Runner failed: %s", string(stderr))
		return "", false
	}

	result := strings.trim_space(string(stdout))
	if len(result) == 0 do return "", false
	return strings.clone(result, context.allocator), true
}
