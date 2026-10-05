# zsh-mini-prompt

A small zsh prompt with smart defaults, configured through zstyle.

<div align="center">
<img src="demo.png">
</div>

## Features

- **Fast**: drawing the prompt takes about 6 ms, even in a repository of 18,000 files with every git status indicator on, because git runs in the background
- **Quiet**: the exit code, the git status and the vi mode show up only when they have something to say, and the right prompt is cleared from lines already run
- **Self-contained**: one file to source, no framework, no external commands besides git, and no dependency on zsh modules such as `colors`
- **Plays well with others**: it never overwrites zle widgets, so it can be sourced before or after any other plugin
- **zsh-native**: configured with zstyle, zsh's own way of storing settings, and laid out with templates you can rearrange freely

## Goals

The prompt is a display of the present, not a record. A line already run keeps only `$ command`, so the scrollback reads as a clean log of what you did. Everything else, such as the directory and the git status, sits on the right while you type and is gone once you press Enter.

Out of the box it shows only what is worth showing, and it does nothing else: no hooks into zle unless you turn on vi mode, no background job unless a template shows git. Each feature you turn on costs only what it needs.

## Why mini

The name comes from where the prompt started. Its predecessor, [ultimate](https://github.com/babarot/ultimate), was a fork of a zsh theme called minimal.

Mini does not mean fewer features. It means the defaults are small and already enough, so most people have nothing to configure, and when you want more, every part can be changed with a zstyle. It uses what zsh already provides (zstyle for settings, prompt escapes like `%F{blue}` for colors, git's own `git-prompt.sh` for git status) instead of inventing its own.

## What it shows

```
$ █                                   ~/src/project (main *+%)
```

- `%sign%`: the prompt sign, `$` by default; red after a failed command if you like, and colored or replaced by the vi mode
- `%path%`: the current directory, in one of three styles
- `%git%`: the branch and its status, computed in the background
- `%exitcode%`: the exit code of the last command, only when it failed
- `%vimode%`: the vi mode as text, such as `N` in normal mode

## Requirements

- zsh 5.3 or later
- git, for `%git%`

## Installation

Clone the repository and source the theme:

```zsh
git clone https://github.com/babarot/zsh-mini-prompt.git
echo 'source /path/to/zsh-mini-prompt/zsh-mini-prompt.zsh-theme' >> ~/.zshrc
```

A plugin manager that sources `*.zsh-theme` files works the same way.

### Load order

There is no order to keep with other plugins. The theme does not depend on the `colors` module, and it registers its zle hooks with `add-zle-hook-widget` alongside the ones other plugins add, so it can be sourced anywhere in your `.zshrc`.

The only rule is that zstyles must be set before the theme is sourced. Templates and the vi mode setting are read once, when it is sourced.

## Configuration

All settings are zstyles under `:prompt:mini:`.

### Templates

The left and right prompts are templates. Place the placeholders above in any order, on either side, mixed with any text or zsh prompt escapes:

```zsh
zstyle ':prompt:mini:left' template '%sign% '                   # default
zstyle ':prompt:mini:right' template '%exitcode% %path% %git%'  # default
```

Colors are plain zsh prompt escapes, so there is nothing new to learn:

```zsh
zstyle ':prompt:mini:right' template '%exitcode% %F{blue}%path%%f %F{242}%git%%f'
```

`%F{color}` and `%f` set and reset the foreground color, `%K{color}` and `%k` the background. A color is a name such as `red`, or a number from `0` to `255`.

### Path

```zsh
zstyle ':prompt:mini:path' style 'minimal'
```

- `minimal`: the last two directories (default)
- `shortpath`: every directory shortened to its first letter except the last, such as `~/s/g/project`
- `fullpath`: the full path, with `~` for the home directory

### Sign

```zsh
zstyle ':prompt:mini:sign' char '>'               # default: $
zstyle ':prompt:mini:sign' color-on-error true    # red after a failed command
```

### Git

Git status comes from `git-prompt.sh`, which ships with the theme. Only the branch is shown by default:

```zsh
zstyle ':prompt:mini:git' show-dirty true      # * unstaged, + staged
zstyle ':prompt:mini:git' show-untracked true  # % untracked files
zstyle ':prompt:mini:git' show-stash true      # $ stashed changes
zstyle ':prompt:mini:git' show-upstream true   # < behind, > ahead, <> diverged, = up to date
```

The status is computed in the background, so it never slows the prompt down. The prompt appears right away and `%git%` fills in once git finishes. Until then it keeps the previous value in the same directory, and stays empty after moving to another one. Nothing runs in the background when no template contains `%git%`.

`format` wraps the status, and the whole of it disappears outside a git repository:

```zsh
zstyle ':prompt:mini:git' format ' (%s)'   # default
```

Put brackets in `format`, not in the template. With `'%path% (%git%)'` an empty `()` is left behind outside a repository; with `format ' (%s)'` nothing is.

### Vi mode

```zsh
zstyle ':prompt:mini:vimode' enable true
```

The sign then takes the color of the current mode. Visual, visual line and replace modes are told apart in plain zsh, with no plugin needed. Each color takes any value `%F{...}` accepts:

```zsh
zstyle ':prompt:mini:vimode' insert-color ''           # default: none
zstyle ':prompt:mini:vimode' normal-color 'white'      # default
zstyle ':prompt:mini:vimode' visual-color 'yellow'     # default
zstyle ':prompt:mini:vimode' visual-line-color 'cyan'  # default: same as visual-color
zstyle ':prompt:mini:vimode' replace-color 'magenta'   # default
```

With `color-on-error`, a failed command still turns the sign red in insert mode.

To show the mode as text, either put `%vimode%` in a template, or let the sign itself turn into the text with `vimode-indicator`:

```zsh
# N$ in normal mode
zstyle ':prompt:mini:left' template '%vimode%%sign% '

# $ in insert mode, N in normal mode
zstyle ':prompt:mini:sign' vimode-indicator true
```

The text for each mode is a zstyle too. Insert mode shows nothing by default, so the sign stays as it is while you type:

```zsh
zstyle ':prompt:mini:vimode' insert-indicator ''        # default: none
zstyle ':prompt:mini:vimode' normal-indicator 'N'       # default
zstyle ':prompt:mini:vimode' visual-indicator 'V'       # default
zstyle ':prompt:mini:vimode' visual-line-indicator 'L'  # default
zstyle ':prompt:mini:vimode' replace-indicator 'R'      # default
```

## Examples

Everything on the left:

```zsh
zstyle ':prompt:mini:left' template '%sign% %path% %git% '
zstyle ':prompt:mini:right' template ''
```

Git first, with short paths:

```zsh
zstyle ':prompt:mini:left' template '%git% %sign% '
zstyle ':prompt:mini:right' template '%exitcode% %path%'
zstyle ':prompt:mini:path' style 'shortpath'
```

Full git status in gray, vi mode in place of the sign:

```zsh
zstyle ':prompt:mini:right' template '%exitcode% %F{242}%git%%f %path%'
zstyle ':prompt:mini:git' format '(%s)'
zstyle ':prompt:mini:git' show-dirty true
zstyle ':prompt:mini:git' show-untracked true
zstyle ':prompt:mini:git' show-stash true
zstyle ':prompt:mini:git' show-upstream true
zstyle ':prompt:mini:sign' color-on-error true
zstyle ':prompt:mini:sign' vimode-indicator true
zstyle ':prompt:mini:vimode' enable true
```

## Configuration reference

| Context | Key | Type | Default | Description |
|---|---|---|---|---|
| `:prompt:mini:left` | `template` | string | `%sign% ` | Left prompt template |
| `:prompt:mini:right` | `template` | string | `%exitcode% %path% %git%` | Right prompt template |
| `:prompt:mini:path` | `style` | string | `minimal` | `minimal`, `shortpath` or `fullpath` |
| `:prompt:mini:sign` | `char` | string | `$` | Prompt sign |
| `:prompt:mini:sign` | `color-on-error` | boolean | `false` | Red sign after a failed command |
| `:prompt:mini:sign` | `vimode-indicator` | boolean | `false` | Show the vi mode indicator in place of the sign |
| `:prompt:mini:git` | `format` | string | ` (%s)` | Text around the git status |
| `:prompt:mini:git` | `show-dirty` | boolean | `false` | Show staged and unstaged changes |
| `:prompt:mini:git` | `show-untracked` | boolean | `false` | Show untracked files |
| `:prompt:mini:git` | `show-stash` | boolean | `false` | Show stashed changes |
| `:prompt:mini:git` | `show-upstream` | boolean | `false` | Show the state against upstream |
| `:prompt:mini:vimode` | `enable` | boolean | `false` | Color the sign by vi mode |
| `:prompt:mini:vimode` | `insert-color` | string | none | Color in insert mode |
| `:prompt:mini:vimode` | `normal-color` | string | `white` | Color in normal mode |
| `:prompt:mini:vimode` | `visual-color` | string | `yellow` | Color in visual mode |
| `:prompt:mini:vimode` | `visual-line-color` | string | `visual-color` | Color in visual line mode |
| `:prompt:mini:vimode` | `replace-color` | string | `magenta` | Color in replace mode |
| `:prompt:mini:vimode` | `insert-indicator` | string | none | Text in insert mode |
| `:prompt:mini:vimode` | `normal-indicator` | string | `N` | Text in normal mode |
| `:prompt:mini:vimode` | `visual-indicator` | string | `V` | Text in visual mode |
| `:prompt:mini:vimode` | `visual-line-indicator` | string | `L` | Text in visual line mode |
| `:prompt:mini:vimode` | `replace-indicator` | string | `R` | Text in replace mode |

## License

MIT

## Credits

zsh-mini-prompt descends from [ultimate](https://github.com/babarot/ultimate), itself a fork of a zsh theme called minimal, and was named za-prompt until it took its current name. Git status comes from git's [git-prompt.sh](https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh).
