#!/bin/zsh
# velocity-integration.zsh
# OSC 133 shell integration for Velocity's embedded terminal.
# Emits prompt/command boundary marks so the terminal can track where
# prompts, commands, and output begin and end.
#
# OSC 133 sequences:
#   A — Prompt started
#   B — Command started (user pressed Enter)
#   C — Command output started
#   D;exitcode — Command finished with exit code
#
# Sourced automatically by TerminalSession when the shell is zsh.
# Uses add-zsh-hook to avoid clobbering user-defined precmd/preexec hooks.

# Guard: only load once per session.
[[ -n "$VELOCITY_SHELL_INTEGRATION_LOADED" ]] && return
export VELOCITY_SHELL_INTEGRATION_LOADED=1

# Require zsh hook system.
autoload -Uz add-zsh-hook

# Track whether a command was actually executed (vs empty Enter).
typeset -g __velocity_command_executed=0

# Track the exit code of the previous command.
typeset -g __velocity_last_exit_code=0

# --- precmd: runs before each prompt is drawn ---
# Emits D (previous command finished) then A (prompt starting) then B (ready for input).
# B is emitted here instead of being embedded in PROMPT to avoid conflicts
# with custom prompt themes (Starship, Powerlevel10k, etc.) that overwrite PROMPT.
__velocity_precmd() {
    __velocity_last_exit_code=$?

    # Emit D (command finished) with exit code — but only if a command ran.
    if (( __velocity_command_executed )); then
        printf '\e]133;D;%d\a' "$__velocity_last_exit_code"
    fi
    __velocity_command_executed=0

    # Emit A (prompt start).
    printf '\e]133;A\a'
}

# --- precmd (late): emits B after all other precmd hooks have run ---
# This ensures B fires after the prompt has been fully composed.
__velocity_precmd_end() {
    printf '\e]133;B\a'
}

# --- preexec: runs after user enters a command, before it executes ---
# Emits C (output start — command is about to produce output).
__velocity_preexec() {
    __velocity_command_executed=1
    printf '\e]133;C\a'
}

# Register hooks. precmd_end fires after all precmd hooks, giving prompt
# themes a chance to set PROMPT before we emit B.
add-zsh-hook precmd __velocity_precmd
add-zsh-hook precmd __velocity_precmd_end
add-zsh-hook preexec __velocity_preexec
