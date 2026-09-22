package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"

// Opens a runner with no input list. This is useful when the runner is acting
// purely as a text box. Set allow_empty when an empty accepted value is useful,
// e.g. opening a bang's base/snap domain
get_runner_input :: proc(
	command: []string,
	allow_empty: bool = false,
) -> (
	output: string,
	ok: bool,
) {
	c := cast(^Config)context.user_ptr
	cmd: []string
	if len(c.empty_runner_cmd) > 0 {
		cmd = c.empty_runner_cmd
	} else {
		if len(command) == 0 {
			fmt.eprintln("Runner command is empty")
			return "", false
		}
		cmd = command
	}

	stdin_read, stdin_write, pipe_err := os.pipe()
	if pipe_err != nil {
		fmt.eprintfln("Failed to create stdin pipe: %v", pipe_err)
		return "", false
	}

	os.close(stdin_write)
	defer os.close(stdin_read)

	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = cmd, stdin = stdin_read},
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
	if len(result) == 0 {
		if allow_empty do return "", true
		return "", false
	}

	return strings.clone(result, context.allocator), true
}

// Opens a runner with a small menu piped to stdin, then returns the selected
// line from stdout. This is deliberately generic; command can be wofi, rofi,
// fuzzel, or anything else that speaks stdin/stdout in the same way
get_runner_choice :: proc(command: []string, input: string) -> (output: string, ok: bool) {
	c := cast(^Config)context.user_ptr
	cmd: []string
	if len(c.browse_runner_cmd) > 0 {
		cmd = c.browse_runner_cmd
	} else {
		if len(command) == 0 {
			fmt.eprintln("Runner command is empty")
			return "", false
		}
		cmd = command
	}

	stdin_read, stdin_write, stdin_err := os.pipe()
	if stdin_err != nil {
		fmt.eprintfln("Failed to create runner stdin pipe: %v", stdin_err)
		return "", false
	}

	stdout_read, stdout_write, stdout_err := os.pipe()
	if stdout_err != nil {
		os.close(stdin_read)
		os.close(stdin_write)
		fmt.eprintfln("Failed to create runner stdout pipe: %v", stdout_err)
		return "", false
	}

	process, start_err := os.process_start(
		os.Process_Desc {
			command = cmd,
			stdin = stdin_read,
			stdout = stdout_write,
			stderr = os.stderr,
		},
	)
	if start_err != nil {
		os.close(stdin_read)
		os.close(stdin_write)
		os.close(stdout_read)
		os.close(stdout_write)
		fmt.eprintfln("Failed to start runner: %v", start_err)
		return "", false
	}

	os.close(stdin_read)
	os.close(stdout_write)

	_, write_err := io.write_full(os.to_stream(stdin_write), transmute([]u8)input)
	os.close(stdin_write)

	stdout_bytes, read_err := os.read_entire_file_from_file(stdout_read, context.allocator)
	os.close(stdout_read)
	defer delete(stdout_bytes)

	state, wait_err := os.process_wait(process)
	if wait_err != nil {
		fmt.eprintfln("Failed waiting for runner: %v", wait_err)
		return "", false
	}

	if !state.exited || state.exit_code != 0 do return "", false

	if write_err != nil {
		fmt.eprintfln("Failed writing data to runner: %v", write_err)
		return "", false
	}

	if read_err != nil {
		fmt.eprintfln("Failed reading runner output: %v", read_err)
		return "", false
	}

	result := strings.trim_space(string(stdout_bytes))
	if len(result) == 0 do return "", false

	return strings.clone(result, context.allocator), true
}
