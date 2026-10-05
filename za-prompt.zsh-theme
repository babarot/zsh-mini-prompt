#!/bin/zsh

# Load git-prompt.sh if it exists
if [[ -f "${0:A:h}/git-prompt.sh" ]]; then
    source "${0:A:h}/git-prompt.sh"
fi

# ======================================================================
# zstyle Configuration
# ======================================================================

# Helper function to get zstyle value with fallback
__prompt_zstyle() {
    local context="$1"
    local key="$2"
    local default="$3"
    local result

    zstyle -s ":prompt:za:${context}" "${key}" result || result="${default}"
    echo "${result}"
}

# Helper function to get zstyle boolean value
__prompt_zstyle_bool() {
    local context="$1"
    local key="$2"
    local default="$3"
    local result

    zstyle -t ":prompt:za:${context}" "${key}" 2>/dev/null && result="true" || result="${default}"
    echo "${result}"
}

# Set default zstyle values if not already set
zstyle -s ':prompt:za:left' template _ || zstyle ':prompt:za:left' template '%sign% '
zstyle -s ':prompt:za:right' template _ || zstyle ':prompt:za:right' template '%exitcode% %path% %git%'
zstyle -s ':prompt:za:path' style _ || zstyle ':prompt:za:path' style 'minimal'
zstyle -s ':prompt:za:sign' char _ || zstyle ':prompt:za:sign' char '$'
zstyle -s ':prompt:za:git' format _ || zstyle ':prompt:za:git' format ' (%s)'
zstyle -t ':prompt:za:vimode' enable 2>/dev/null || zstyle ':prompt:za:vimode' enable false
zstyle -s ':prompt:za:vimode' normal-color _ || zstyle ':prompt:za:vimode' normal-color 'white'
zstyle -s ':prompt:za:vimode' visual-color _ || zstyle ':prompt:za:vimode' visual-color 'yellow'
zstyle -s ':prompt:za:vimode' replace-color _ || zstyle ':prompt:za:vimode' replace-color 'magenta'

__shorten_path() {
    setopt localoptions noksharrays extendedglob
    local MATCH MBEGIN MEND
    local -a match mbegin mend
    "${2:-echo}" "${1//(#m)[^\/]##\//${MATCH/(#b)([^.])*/$match[1]}/}"
}

__prompt_path() {
    local cwd
    local path_style="$(__prompt_zstyle "path" "style" "minimal")"

    case "${path_style}" in
        "fullpath")
            cwd="$(print -D "${PWD}")"
            ;;
        "shortpath")
            cwd="$(__shorten_path "${PWD/#$HOME/~}")"
            ;;
        "minimal")
            cwd="$(print -P %2~)"
            ;;
        *)
            cwd=
            ;;
    esac
    echo "$cwd"
}

__prompt_exitcode() {
    echo "%(?..%F{red}%? ⏎  %f) "
}

__prompt_git() {
    # Check if __git_ps1 function exists (git-prompt.sh loaded)
    if ! type __git_ps1 &>/dev/null; then
        return 0
    fi

    # Configure git-prompt.sh behavior from zstyle
    if zstyle -t ':prompt:za:git' show-dirty 2>/dev/null; then
        export GIT_PS1_SHOWDIRTYSTATE=1
    fi
    if zstyle -t ':prompt:za:git' show-untracked 2>/dev/null; then
        export GIT_PS1_SHOWUNTRACKEDFILES=1
    fi
    if zstyle -t ':prompt:za:git' show-stash 2>/dev/null; then
        export GIT_PS1_SHOWSTASHSTATE=1
    fi
    if zstyle -t ':prompt:za:git' show-upstream 2>/dev/null; then
        export GIT_PS1_SHOWUPSTREAM="auto"
    fi

    # Get git format from zstyle
    local git_format="$(__prompt_zstyle "git" "format" " (%s)")"

    # Call __git_ps1 with formatting
    local git_info="$(__git_ps1 "${git_format}")"
    if [[ -n "${git_info}" ]]; then
        echo "${git_info}"
    fi
}

# %git% is computed in the background and shown once it is ready.
# __prompt_git_pwd is the directory __prompt_git_result was computed in.
__prompt_git_result=""
__prompt_git_pwd=""
__prompt_git_fd=""
__prompt_git_pid=""

# Discard the running job, if any. Only its subshell is killed; a git
# command already started under it runs to the end with nowhere to write.
__prompt_git_async_stop() {
    [[ -n "${__prompt_git_fd}" ]] || return 0
    zle -F "${__prompt_git_fd}" 2>/dev/null
    exec {__prompt_git_fd}<&-
    kill "${__prompt_git_pid}" 2>/dev/null
    __prompt_git_fd=""
    __prompt_git_pid=""
}

__prompt_git_async_start() {
    __prompt_git_async_stop

    # Keep the last result while computing, but not for another directory
    if [[ "${__prompt_git_pwd}" != "${PWD}" ]]; then
        __prompt_git_result=""
    fi

    # Process substitution does not set $!, so the job writes its pid first.
    # Reading that line here waits only for the fork; the handler is
    # registered after it and wakes up for the result alone.
    # The job may still run when the next command starts, so it must not
    # take index.lock away from that command.
    exec {__prompt_git_fd}< <(
        print -r -- "${sysparams[pid]}"
        export GIT_OPTIONAL_LOCKS=0
        __prompt_git
    )
    read -r -u "${__prompt_git_fd}" __prompt_git_pid
    zle -F -w "${__prompt_git_fd}" __prompt_git_async_done
}

# A cd inside a zle widget (e.g. a fuzzy cd) redraws without precmd.
# Outside zle the next precmd starts the job, and a cd in a subshell
# must not start one at all.
__prompt_git_async_chpwd() {
    zle && __prompt_git_async_start
}

__prompt_git_async_done() {
    local fd="$1" result
    IFS= read -r -d '' -u "${fd}" result
    zle -F "${fd}"
    exec {fd}<&-
    [[ "${fd}" == "${__prompt_git_fd}" ]] || return 0

    __prompt_git_fd=""
    __prompt_git_pid=""
    __prompt_git_result="${result%$'\n'}"
    __prompt_git_pwd="${PWD}"
    zle reset-prompt
}

# Current vi mode: insert, normal, visual, visual-line or replace.
# Stays empty unless vimode is enabled.
__prompt_vimode=""

# Visual mode does not change the keymap and replace mode stays in the
# insert keymap, so the mode is read before every redraw instead of on
# keymap-select.
__prompt_vimode_update() {
    local mode
    case ${KEYMAP} in
        vicmd)
            case ${REGION_ACTIVE} in
                1) mode="visual" ;;
                2) mode="visual-line" ;;
                *) mode="normal" ;;
            esac
            ;;
        main|viins)
            if [[ ${ZLE_STATE} == *overwrite* ]]; then
                mode="replace"
            else
                mode="insert"
            fi
            ;;
        *)
            # Keymaps such as isearch or menuselect keep the current mode
            return 0
            ;;
    esac

    # Runs on every redraw, so redraw the prompt only when the mode changes
    [[ ${mode} == ${__prompt_vimode} ]] && return 0
    __prompt_vimode="${mode}"
    zle reset-prompt
}

# Every new line starts in insert mode, so reset before the prompt is drawn
__prompt_vimode_precmd() {
    __prompt_vimode="insert"
}

__prompt_sign() {
    local sign color color_on_error
    zstyle -s ':prompt:za:sign' char sign || sign='$'
    zstyle -t ':prompt:za:sign' color-on-error && color_on_error=true

    # Escape % character for prompt
    sign="${sign//\%/%%}"

    case ${__prompt_vimode} in
        visual-line)
            zstyle -s ':prompt:za:vimode' visual-line-color color ||
                zstyle -s ':prompt:za:vimode' visual-color color
            ;;
        ?*)
            zstyle -s ':prompt:za:vimode' "${__prompt_vimode}-color" color
            ;;
    esac
    local colored="${sign}"
    [[ -n "${color}" ]] && colored="%F{${color}}${sign}%f"

    # A failed command turns the sign red, but only in insert mode
    if [[ "${color_on_error}" == "true" && ${__prompt_vimode:-insert} == insert ]]; then
        echo "%(?.${colored}.%F{red}${sign}%f)"
    else
        echo "${colored}"
    fi
}

# Parse template and replace placeholders
__prompt_parse_template() {
    local template="$1"
    local result="${template}"

    # Replace placeholders with actual values
    result="${result//\%sign\%/\$(__prompt_sign)}"
    result="${result//\%git\%/\${__prompt_git_result\}}"
    result="${result//\%path\%/\$(__prompt_path)}"
    result="${result//\%exitcode\%/\$(__prompt_exitcode)}"

    echo "${result}"
}

__prompt_main() {
    # Allow for functions in the prompt.
    setopt PROMPT_SUBST
    # Hide old prompt
    setopt TRANSIENT_RPROMPT

    # Hook into zle only when vi mode indicator is enabled
    if zstyle -t ':prompt:za:vimode' enable; then
        autoload -Uz add-zle-hook-widget add-zsh-hook
        add-zle-hook-widget line-pre-redraw __prompt_vimode_update
        add-zsh-hook precmd __prompt_vimode_precmd
    fi

    # Get templates from zstyle
    local left_template="$(__prompt_zstyle "left" "template" "%sign% ")"
    local right_template="$(__prompt_zstyle "right" "template" "%exitcode% %path% %git%")"

    # Run the git job only when a template shows it
    if [[ "${left_template}${right_template}" == *%git%* ]]; then
        zmodload zsh/system
        autoload -Uz add-zsh-hook
        zle -N __prompt_git_async_done
        add-zsh-hook precmd __prompt_git_async_start
        add-zsh-hook chpwd __prompt_git_async_chpwd
    fi

    # Parse templates and set prompts
    PROMPT="$(__prompt_parse_template "${left_template}")"
    RPROMPT="$(__prompt_parse_template "${right_template}")"
}

__prompt_main
