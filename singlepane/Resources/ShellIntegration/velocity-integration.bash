#!/bin/bash
# velocity-integration.bash
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
# Sourced automatically by TerminalSession when the shell is bash.
# Appends to PROMPT_COMMAND and uses a DEBUG trap for preexec behavior.

# Guard: only load once per session.
[[ -n "$VELOCITY_SHELL_INTEGRATION_LOADED" ]] && return
export VELOCITY_SHELL_INTEGRATION_LOADED=1

# Track whether a command was actually executed (vs empty Enter).
__velocity_command_executed=0

# Track whether we're inside the prompt command (to skip DEBUG trap during it).
__velocity_in_prompt_command=0

# --- prompt_command: runs before each prompt is drawn ---
# Emits D (previous command finished) then A (prompt starting) then B (ready for input).
__velocity_prompt_command() {
    local exit_code=$?
    __velocity_in_prompt_command=1

    # Emit D (command finished) with exit code — but only if a command ran.
    if [[ "$__velocity_command_executed" == "1" ]]; then
        printf '\e]133;D;%d\a' "$exit_code"
    fi
    __velocity_command_executed=0

    # Emit A (prompt start) and B (command input ready).
    printf '\e]133;A\a'
    printf '\e]133;B\a'

    __velocity_in_prompt_command=0
}

# --- debug trap: fires before each command executes ---
# Acts as a preexec equivalent. Emits C (output start).
__velocity_debug_trap() {
    # Skip if we're inside PROMPT_COMMAND execution.
    [[ "$__velocity_in_prompt_command" == "1" ]] && return

    # Only emit C once per command (first statement in a pipeline/compound).
    if [[ "$__velocity_command_executed" == "0" ]]; then
        __velocity_command_executed=1
        printf '\e]133;C\a'
    fi
}

# Append to PROMPT_COMMAND — supports both array (bash 5.1+) and string forms.
if [[ ${BASH_VERSINFO[0]} -ge 5 && ${BASH_VERSINFO[1]} -ge 1 ]]; then
    PROMPT_COMMAND=(__velocity_prompt_command "${PROMPT_COMMAND[@]}")
else
    PROMPT_COMMAND="__velocity_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi

# Install the DEBUG trap. Preserve any existing trap.
__velocity_existing_trap=$(trap -p DEBUG | sed "s/trap -- '\\(.*\\)' DEBUG/\\1/")
if [[ -n "$__velocity_existing_trap" ]]; then
    trap '__velocity_debug_trap; '"$__velocity_existing_trap" DEBUG
else
    trap '__velocity_debug_trap' DEBUG
fi
