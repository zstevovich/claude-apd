#!/bin/bash
# APD Agent Log Parser — extracts dispatch counts from .agents log
#
# An agent entry is `ts|event|agent_type|agent_id` where event ∈ {start,stop}.
# When the SubagentStop hook fires, it writes a stop event. A start with no
# matching stop is a DROPPED SubagentStop hook (or a resume still running) —
# not a maxTurn exhaust: a subagent that hits its `maxTurns` stops with a
# PARTIAL result and its stop fires (re-measured 2026-10-01, CC 2.1.286).
# A resume via SendMessage fires another SubagentStart with the SAME id, so
# one dispatch can leave several start lines and one stop (measured 8 + 1);
# this parser still counts each start line — reading a same-id re-start as a
# resume is the next patch.
#
# parse_agents_log FILE → prints "TOTAL EXHAUSTED" to stdout
#   TOTAL     = number of start events
#   EXHAUSTED = number of start events with no matching stop for same agent_id
#               (legacy name; it is the dropped-stop count)

parse_agents_log() {
    local log_file="$1"
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        printf '0 0'
        return
    fi

    awk -F'|' '
        $2=="start" { started[$4]=1; total++ }
        $2=="stop"  { stopped[$4]=1 }
        END {
            exhausted = 0
            for (aid in started) if (!(aid in stopped)) exhausted++
            printf "%d %d", total+0, exhausted+0
        }
    ' "$log_file"
}
