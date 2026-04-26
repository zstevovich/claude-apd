#!/bin/bash
# APD Agent Log Parser — extracts dispatch counts from .agents log
#
# An agent entry is `ts|event|agent_type|agent_id` where event ∈ {start,stop}.
# When SubagentStop hook fires, it writes a stop event. If the agent exhausts
# its maxTurn budget, the runtime terminates the session without firing the
# hook, so the log has start without matching stop for that agent_id.
#
# parse_agents_log FILE → prints "TOTAL EXHAUSTED" to stdout
#   TOTAL     = number of start events
#   EXHAUSTED = number of start events with no matching stop for same agent_id

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
