#!/bin/zsh

# Load git-prompt.sh if it exists
if [[ -f "${0:A:h}/git-prompt.sh" ]]; then
    source "${0:A:h}/git-prompt.sh"
fi

# ======================================================================
# zstyle Configuration
# ======================================================================

# Helper function to get zstyle value with fallback
__mini_prompt_zstyle() {
    local context="$1"
    local key="$2"
    local default="$3"
    local result

    zstyle -s ":prompt:mini:${context}" "${key}" result || result="${default}"
    echo "${result}"
}

# Helper function to get zstyle boolean value
__mini_prompt_zstyle_bool() {
    local context="$1"
    local key="$2"
    local default="$3"
    local result

    zstyle -t ":prompt:mini:${context}" "${key}" 2>/dev/null && result="true" || result="${default}"
    echo "${result}"
}

# Set default zstyle values if not already set
zstyle -s ':prompt:mini:left' template _ || zstyle ':prompt:mini:left' template '%sign% '
zstyle -s ':prompt:mini:right' template _ || zstyle ':prompt:mini:right' template '%exitcode% %path% %git%'
zstyle -s ':prompt:mini:path' style _ || zstyle ':prompt:mini:path' style 'minimal'
zstyle -s ':prompt:mini:sign' char _ || zstyle ':prompt:mini:sign' char '$'
zstyle -s ':prompt:mini:git' format _ || zstyle ':prompt:mini:git' format ' (%s)'
zstyle -t ':prompt:mini:vimode' enable 2>/dev/null || zstyle ':prompt:mini:vimode' enable false
zstyle -s ':prompt:mini:vimode' normal-color _ || zstyle ':prompt:mini:vimode' normal-color 'white'
zstyle -s ':prompt:mini:vimode' visual-color _ || zstyle ':prompt:mini:vimode' visual-color 'yellow'
zstyle -s ':prompt:mini:vimode' replace-color _ || zstyle ':prompt:mini:vimode' replace-color 'magenta'
zstyle -s ':prompt:mini:vimode' normal-indicator _ || zstyle ':prompt:mini:vimode' normal-indicator 'N'
zstyle -s ':prompt:mini:vimode' visual-indicator _ || zstyle ':prompt:mini:vimode' visual-indicator 'V'
zstyle -s ':prompt:mini:vimode' visual-line-indicator _ || zstyle ':prompt:mini:vimode' visual-line-indicator 'L'
zstyle -s ':prompt:mini:vimode' replace-indicator _ || zstyle ':prompt:mini:vimode' replace-indicator 'R'

__mini_prompt_shorten_path() {
    setopt localoptions noksharrays extendedglob
    local MATCH MBEGIN MEND
    local -a match mbegin mend
    "${2:-echo}" "${1//(#m)[^\/]##\//${MATCH/(#b)([^.])*/$match[1]}/}"
}

__mini_prompt_path() {
    local cwd
    local path_style="$(__mini_prompt_zstyle "path" "style" "minimal")"

    case "${path_style}" in
        "fullpath")
            cwd="$(print -D "${PWD}")"
            ;;
        "shortpath")
            cwd="$(__mini_prompt_shorten_path "${PWD/#$HOME/~}")"
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

__mini_prompt_exitcode() {
    echo "%(?..%F{red}%? ⏎  %f) "
}

__mini_prompt_git() {
    # Check if __git_ps1 function exists (git-prompt.sh loaded)
    if ! type __git_ps1 &>/dev/null; then
        return 0
    fi

    # Configure git-prompt.sh behavior from zstyle
    if zstyle -t ':prompt:mini:git' show-dirty 2>/dev/null; then
        export GIT_PS1_SHOWDIRTYSTATE=1
    fi
    if zstyle -t ':prompt:mini:git' show-untracked 2>/dev/null; then
        export GIT_PS1_SHOWUNTRACKEDFILES=1
    fi
    if zstyle -t ':prompt:mini:git' show-stash 2>/dev/null; then
        export GIT_PS1_SHOWSTASHSTATE=1
    fi
    if zstyle -t ':prompt:mini:git' show-upstream 2>/dev/null; then
        export GIT_PS1_SHOWUPSTREAM="auto"
    fi

    # Get git format from zstyle
    local git_format="$(__mini_prompt_zstyle "git" "format" " (%s)")"

    # Call __git_ps1 with formatting
    local git_info="$(__git_ps1 "${git_format}")"
    if [[ -n "${git_info}" ]]; then
        echo "${git_info}"
    fi
}

# %git% is computed in the background and shown once it is ready.
# __mini_prompt_git_pwd is the directory __mini_prompt_git_result was computed in.
__mini_prompt_git_result=""
__mini_prompt_git_pwd=""
__mini_prompt_git_fd=""
__mini_prompt_git_pid=""

# Discard the running job, if any. Only its subshell is killed; a git
# command already started under it runs to the end with nowhere to write.
__mini_prompt_git_async_stop() {
    [[ -n "${__mini_prompt_git_fd}" ]] || return 0
    zle -F "${__mini_prompt_git_fd}" 2>/dev/null
    exec {__mini_prompt_git_fd}<&-
    kill "${__mini_prompt_git_pid}" 2>/dev/null
    __mini_prompt_git_fd=""
    __mini_prompt_git_pid=""
}

__mini_prompt_git_async_start() {
    __mini_prompt_git_async_stop

    # Keep the last result while computing, but not for another directory
    if [[ "${__mini_prompt_git_pwd}" != "${PWD}" ]]; then
        __mini_prompt_git_result=""
    fi

    # Process substitution does not set $!, so the job writes its pid first.
    # Reading that line here waits only for the fork; the handler is
    # registered after it and wakes up for the result alone.
    # The job may still run when the next command starts, so it must not
    # take index.lock away from that command.
    exec {__mini_prompt_git_fd}< <(
        print -r -- "${sysparams[pid]}"
        export GIT_OPTIONAL_LOCKS=0
        __mini_prompt_git
    )
    read -r -u "${__mini_prompt_git_fd}" __mini_prompt_git_pid
    zle -F -w "${__mini_prompt_git_fd}" __mini_prompt_git_async_done
}

# A cd inside a zle widget (e.g. a fuzzy cd) redraws without precmd.
# Outside zle the next precmd starts the job, and a cd in a subshell
# must not start one at all.
__mini_prompt_git_async_chpwd() {
    zle && __mini_prompt_git_async_start
}

__mini_prompt_git_async_done() {
    local fd="$1" result
    IFS= read -r -d '' -u "${fd}" result
    zle -F "${fd}"
    exec {fd}<&-
    [[ "${fd}" == "${__mini_prompt_git_fd}" ]] || return 0

    __mini_prompt_git_fd=""
    __mini_prompt_git_pid=""
    __mini_prompt_git_result="${result%$'\n'}"
    __mini_prompt_git_pwd="${PWD}"
    zle reset-prompt
}

# Current vi mode: insert, normal, visual, visual-line or replace.
# Stays empty unless vimode is enabled.
__mini_prompt_vimode=""

# Visual mode does not change the keymap and replace mode stays in the
# insert keymap, so the mode is read before every redraw instead of on
# keymap-select.
__mini_prompt_vimode_update() {
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
    [[ ${mode} == ${__mini_prompt_vimode} ]] && return 0
    __mini_prompt_vimode="${mode}"
    zle reset-prompt
}

# Every new line starts in insert mode, so reset before the prompt is drawn
__mini_prompt_vimode_precmd() {
    __mini_prompt_vimode="insert"
}

# Set REPLY to the color of the current vi mode, empty when there is none
__mini_prompt_vimode_color() {
    REPLY=""
    case ${__mini_prompt_vimode} in
        visual-line)
            zstyle -s ':prompt:mini:vimode' visual-line-color REPLY ||
                zstyle -s ':prompt:mini:vimode' visual-color REPLY
            ;;
        ?*)
            zstyle -s ':prompt:mini:vimode' "${__mini_prompt_vimode}-color" REPLY
            ;;
    esac
}

__mini_prompt_sign() {
    local sign color_on_error
    zstyle -s ':prompt:mini:sign' char sign || sign='$'
    zstyle -t ':prompt:mini:sign' color-on-error && color_on_error=true

    # Show the mode's indicator in place of the sign, where it has one
    if [[ -n "${__mini_prompt_vimode}" ]] && zstyle -t ':prompt:mini:sign' vimode-indicator; then
        local indicator
        zstyle -s ':prompt:mini:vimode' "${__mini_prompt_vimode}-indicator" indicator
        [[ -n "${indicator}" ]] && sign="${indicator}"
    fi

    # Escape % character for prompt
    sign="${sign//\%/%%}"

    local REPLY
    __mini_prompt_vimode_color
    local colored="${sign}"
    [[ -n "${REPLY}" ]] && colored="%F{${REPLY}}${sign}%f"

    # A failed command turns the sign red, but only in insert mode
    if [[ "${color_on_error}" == "true" && ${__mini_prompt_vimode:-insert} == insert ]]; then
        echo "%(?.${colored}.%F{red}${sign}%f)"
    else
        echo "${colored}"
    fi
}

# Text for the current vi mode, in the mode's color
__mini_prompt_vimode_indicator() {
    [[ -n "${__mini_prompt_vimode}" ]] || return 0

    local indicator
    zstyle -s ':prompt:mini:vimode' "${__mini_prompt_vimode}-indicator" indicator
    [[ -n "${indicator}" ]] || return 0
    indicator="${indicator//\%/%%}"

    local REPLY
    __mini_prompt_vimode_color
    if [[ -n "${REPLY}" ]]; then
        echo "%F{${REPLY}}${indicator}%f"
    else
        echo "${indicator}"
    fi
}

# Parse template and replace placeholders
__mini_prompt_parse_template() {
    local template="$1"
    local result="${template}"

    # Replace placeholders with actual values
    result="${result//\%sign\%/\$(__mini_prompt_sign)}"
    result="${result//\%vimode\%/\$(__mini_prompt_vimode_indicator)}"
    result="${result//\%git\%/\${__mini_prompt_git_result\}}"
    result="${result//\%path\%/\$(__mini_prompt_path)}"
    result="${result//\%exitcode\%/\$(__mini_prompt_exitcode)}"

    echo "${result}"
}

__mini_prompt_main() {
    # Allow for functions in the prompt.
    setopt PROMPT_SUBST
    # Hide old prompt
    setopt TRANSIENT_RPROMPT

    # Hook into zle only when vi mode indicator is enabled
    if zstyle -t ':prompt:mini:vimode' enable; then
        autoload -Uz add-zle-hook-widget add-zsh-hook
        add-zle-hook-widget line-pre-redraw __mini_prompt_vimode_update
        add-zsh-hook precmd __mini_prompt_vimode_precmd
    fi

    # Get templates from zstyle
    local left_template="$(__mini_prompt_zstyle "left" "template" "%sign% ")"
    local right_template="$(__mini_prompt_zstyle "right" "template" "%exitcode% %path% %git%")"

    # Run the git job only when a template shows it
    if [[ "${left_template}${right_template}" == *%git%* ]]; then
        zmodload zsh/system
        autoload -Uz add-zsh-hook
        zle -N __mini_prompt_git_async_done
        add-zsh-hook precmd __mini_prompt_git_async_start
        add-zsh-hook chpwd __mini_prompt_git_async_chpwd
    fi

    # Parse templates and set prompts
    PROMPT="$(__mini_prompt_parse_template "${left_template}")"
    RPROMPT="$(__mini_prompt_parse_template "${right_template}")"
}

__mini_prompt_main
