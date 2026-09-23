# obang

`obang` is a small Odin utility for resolving browser bangs outside the browser

It uses the [Kagi bangs](https://github.com/kagisearch/bangs) database as its main
source, with support for layering external bang files and inline custom bangs
on top

Bangs can be resolved directly from the terminal, passed through a launcher such
as Wofi, searched or browsed interactively, or printed as resolved URLs for use
in external scripts, other tools and so on

## Features

- Kagi bangs as the default bang source
- Optional Kagi-free mode
- Local cached bang database
- Custom bangs and overrides
- External json bang files
- Deterministic merge precedence
- Alias claiming between custom and existing bangs
- Configurable bang prefix
- Optional lazy bangs
- Direct terminal bang resolution
- Print mode for resolved URLs
- Runner / launcher integration
- Interactive browsing by category and subcategory
- Fuzzy terminal search
- Exact lookup by trigger or alias
- Human-readable or json bang details
- Configurable browser commands
- Configurable runner commands
- Fish, Bash, and Zsh completions

## How it works

The loaded bang database is built in this order:

```text
Kagi bangs (when enabled)
    ↓
custom.files[0]
    ↓
custom.files[1]
    ↓
...
    ↓
custom.bangs
```

Later sources override earlier ones, so inline `custom.bangs` are always the
final authority

If `disable_kagi_bangs` is enabled, the Kagi layer is skipped entirely:

```text
custom.files → custom.bangs
```

If no bangs are available after loading, `obang` exits with an error

## Building

Requires [Odin](https://odin-lang.org/) and `git`

From the project directory:

```sh
odin build src -out:obang
```

Then place the binary somewhere on your `PATH`, for example:

```sh
install -Dm755 obang ~/.local/bin/obang
```

## Usage

```text
obang cmd [tab] [print] !bang [query ...]
obang runner [print] <runner command ...>
obang browse <runner command ...>
obang search <name ...>
obang get [-j|--json] <trigger-or-alias>
obang count
obang update
obang completions <fish|bash|zsh>
```

### Resolve a bang

```sh
obang cmd !yt odin lang
```

Open the result in a new browser tab:

```sh
obang cmd -t !yt odin lang
```

Print the resolved URL instead of opening it:

```sh
obang cmd -p !yt odin lang
```

This makes `obang` easy to compose with other tools:

```sh
url="$(obang cmd -p !yt odin lang)"
printf '%s\n' "$url"
```

### Runner mode

`runner` sends input through a dmenu-compatible launcher and resolves the
returned text:

```sh
obang runner wofi --dmenu --prompt obang
```

Print the resulting URL instead of opening it:

```sh
obang runner -p wofi --dmenu --prompt obang
```

When `runner_settings.empty_runner_cmd` is configured, it is used automatically,
so the runner command does not need to be supplied each time

### Browse bangs

```sh
obang browse wofi --dmenu --prompt obang
```

Browse mode provides searchable bang, category, and subcategory menus

Cancelling a nested selection moves back to the previous menu. The entire browse
session can also be exited with `SIGINT`

### Search

Fuzzy-search bang names from the terminal:

```sh
obang search youtube music
```

### Inspect a bang

Look up a bang by trigger:

```sh
obang get !yt
```

Aliases work too:

```sh
obang get yt
```

Print the full bang as json:

```sh
obang get -j !yt
```

### Count loaded bangs

```sh
obang count
```

### Update the Kagi database

```sh
obang update
```

The Kagi repository and normalized bang database are cached under:

```text
~/.cache/obang/
```

## Configuration

Configuration lives at:

```text
~/.config/obang/config.json
```

A representative configuration looks like this:

```json
{
  "custom": {
    "files": [
      "bangs/media.json",
      "~/.config/obang/bangs/work.json"
    ],
    "bangs": [
      {
        "name": "Wikipedia",
        "trigger": "wikipedia",
        "triggers": ["wiki"],
        "template": "https://wikipedia.org/w/index.php?search={{{s}}}"
      }
    ]
  },
  "runner_settings": {
    "empty_runner_cmd": [
      "wofi",
      "-d",
      "-W",
      "25%",
      "-H",
      "10%"
    ],
    "browse_root_runner_cmd": [
      "wofi",
      "-d",
      "-p",
      "obang",
      "-W",
      "30%",
      "-L",
      "3"
    ],
    "browse_bang_runner_cmd": [
      "wofi",
      "-d",
      "-p",
      "pick bang",
      "-W",
      "45%",
      "-H",
      "30%"
    ],
    "browse_category_runner_cmd": [
      "wofi",
      "-d",
      "-p",
      "pick category",
      "-W",
      "30%",
      "-H",
      "30%"
    ],
    "browse_subcategory_runner_cmd": [
      "wofi",
      "-d",
      "-p",
      "pick subcategory",
      "-W",
      "30%",
      "-H",
      "30%"
    ]
  },
  "general_settings": {
    "browser_cmd_prefix": "firefox",
    "browser_win_prefix": "--new-window",
    "browser_tab_prefix": "--new-tab",
    "default_bounce_bang": "!google",
    "alternate_prefix": "",
    "allow_notifications": false,
    "lazy_bangs": false,
    "disable_kagi_bangs": false
  }
}
```

## Custom bangs

A custom bang only requires three fields:

```json
{
  "name": "Example",
  "trigger": "ex",
  "template": "https://example.com/search?q={{{s}}}"
}
```

The full supported shape is:

```json
{
  "name": "Example",
  "domain": "example.com",
  "snap_domain": "example.com",
  "trigger": "ex",
  "triggers": [
    "example",
    "e"
  ],
  "template": "https://example.com/search?q={{{s}}}",
  "regex_pattern": "",
  "category": "Custom",
  "subcategory": "Example",
  "format": [
    "url_encode_placeholder",
    "url_encode_space_to_plus"
  ]
}
```

`name`, `trigger`, and `template` are required - Everything else is optional

### Overrides

A custom bang can override an existing loaded bang by matching its name or
primary trigger

Optional fields only replace the existing value when supplied by the custom bang.
This makes small overrides possible without copying the entire Kagi entry

Aliases have three useful behaviours
Omitting `triggers` keeps the existing aliases:

```json
{
  "name": "Wikipedia",
  "trigger": "wikipedia",
  "template": "..."
}
```

Supplying `triggers` replaces the existing aliases:

```json
"triggers": ["wiki"]
```

An explicitly empty list removes all aliases:

```json
"triggers": []
```

Custom aliases are also claimed from other loaded bangs, preventing the same
alias from resolving to multiple entries

## External bang files

Large custom bang collections do not need to live directly inside `config.json`
Reference them using `custom.files`:

```json
{
  "custom": {
    "files": [
      "bangs/media.json",
      "bangs/work.json"
    ],
    "bangs": []
  }
}
```

Each referenced file contains a plain json array of bang objects:

```json
[
  {
    "name": "WatchSeries",
    "domain": "ww8.watchseriesfree.co",
    "trigger": "wat",
    "triggers": ["watch", "ws"],
    "template": "https://ww8.watchseriesfree.co/search/?q={{{s}}}",
    "category": "Entertainment"
  },
  {
    "name": "Example",
    "trigger": "ex",
    "template": "https://example.com/search?q={{{s}}}"
  }
]
```

Paths may be absolute, home-relative, or relative to the `obang` config directory:

```text
/absolute/path.json
~/bangs/example.json
bangs/example.json
```

Referenced files are validated at startup. Invalid paths, unreadable files,
malformed json, or bangs missing required fields cause startup to fail, rather
than silently producing a partial database

## Bang prefixes

Internally, bang resolution always uses the canonical `!` prefix.

`alternate_prefix` only changes the user-facing syntax. For example:

```json
"alternate_prefix": "@"
```

allows:

```sh
obang cmd @yt cats
```

while the underlying bang database remains unchanged

### Lazy bangs

With:

```json
"lazy_bangs": true
```

an unprefixed runner input such as:

```text
yt cats
```

is first treated as though the configured bang prefix had been supplied
If it does not resolve as a bang, runner mode can still fall back through
`default_bounce_bang` (if set)

## Disable Kagi bangs

For a completely custom database:

```json
"disable_kagi_bangs": true
```

Kagi bangs will not be loaded.
External files and inline custom bangs continue to work normally
If this leaves the database empty, `obang` exits with an error

## Runner configuration

Each browse stage can use its own runner command:

- `empty_runner_cmd` — free-text input
- `browse_root_runner_cmd` — root browse menu
- `browse_bang_runner_cmd` — bang and result selection
- `browse_category_runner_cmd` — category selection
- `browse_subcategory_runner_cmd` — subcategory selection

This allows each Wofi, Rofi, dmenu, or compatible view to use its own dimensions,
prompt, styling, and other arguments

## Shell completions

Completion definitions query `obang` dynamically, so triggers and aliases do not
need to be baked into the generated scripts

### Fish

```sh
mkdir -p ~/.config/fish/completions
obang completions fish > ~/.config/fish/completions/obang.fish
```

### Bash

```sh
mkdir -p ~/.local/share/bash-completion/completions
obang completions bash > ~/.local/share/bash-completion/completions/obang
```

### Zsh

```sh
mkdir -p ~/.zfunc
obang completions zsh > ~/.zfunc/_obang
```

Then ensure `~/.zfunc` is on `fpath`:

```zsh
fpath=(~/.zfunc $fpath)
autoload -Uz compinit
compinit
```

## Template support

`obang` supports the Kagi-style search placeholder:

```text
{{{s}}}
```

It also supports regex-backed `$1`, `$2`, ... replacement templates where
defined, by a bang
Supported formatting flags:

```text
url_encode_placeholder
url_encode_space_to_plus
open_snap_domain
open_base_path
```

These control query encoding and empty-query behaviour

If `format` is omitted or `null`, all formatting flags are treated as enabled
by default. To disable a specific behaviour, provide an explicit `format`
array containing only the flags you want

## Why obang?

Browser-native bangs are convenient, but they tie bang resolution to a browser's
address bar

`obang` moves that resolution into a small standalone tool, making bangs usable
from launchers, shell scripts, keybindings, desktop workflows, and anything else
that can invoke a command

The goal is simple: keep the convenience of bangs, but make them available
everywhere

## Credits

The default bang database comes from the
[Kagi bangs project](https://github.com/kagisearch/bangs)

`obang` is not affiliated with Kagi
