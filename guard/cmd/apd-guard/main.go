// apd-guard — APD's guards that read shell commands, in one binary.
//
//	apd-guard bash-scope --project-dir <dir> --command <cmd> [--cwd <dir>] [--deny-all-writes] [scope ...]
//	apd-guard git --command <cmd> [--agent-type <type>]
//	apd-guard spec-blind --project-dir <dir> --pipeline-dir <dir> --memory-dir <dir> --agent-type <type> [--tool <name>] [--file-path <path>] [--command <cmd>]
//
// Exit 0 allows, exit 2 blocks (the reason goes to stderr). This is the judge
// only: it reads, it never writes.
package main

import (
	"fmt"
	"os"

	"github.com/zstevovich/claude-apd/guard/internal/bashscope"
	"github.com/zstevovich/claude-apd/guard/internal/gitguard"
	"github.com/zstevovich/claude-apd/guard/internal/specblind"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: apd-guard bash-scope --project-dir <dir> --command <cmd> [--cwd <dir>] [--deny-all-writes] [scope ...]")
		os.Exit(64)
	}
	switch os.Args[1] {
	case "bash-scope":
		o := bashscope.Options{Home: os.Getenv("HOME"), TmpDir: os.Getenv("TMPDIR"), PluginRoot: os.Getenv("CLAUDE_PLUGIN_ROOT")}
		args := os.Args[2:]
		for i := 0; i < len(args); i++ {
			next := func() string {
				i++
				if i < len(args) {
					return args[i]
				}
				return ""
			}
			switch args[i] {
			case "--command":
				o.Command = next()
			case "--cwd":
				o.Cwd = next()
			case "--project-dir":
				o.ProjectDir = next()
			case "--apd-root":
				o.ApdRoot = next()
			case "--deny-all-writes":
				o.DenyAllWrites = true
			default:
				o.Scope = append(o.Scope, args[i])
			}
		}
		if v := bashscope.Judge(o); v.Blocked() {
			fmt.Fprintf(os.Stderr, "%s: %s\n", v.Code, v.Detail)
			os.Exit(2)
		}
	case "git":
		// apd-guard git --command <cmd> [--agent-type <type>]
		// A signed commit that passed prints `commit` on stdout: the caller runs the gate.
		var o gitguard.Options
		args := os.Args[2:]
		for i := 0; i+1 < len(args); i += 2 {
			switch args[i] {
			case "--command":
				o.Command = args[i+1]
			case "--agent-type":
				o.AgentType = args[i+1]
			}
		}
		v := gitguard.Judge(o)
		if v.Blocked() {
			fmt.Fprintf(os.Stderr, "%s: BLOCKED: %s\n", v.Code, v.Message)
			os.Exit(2)
		}
		if v.Commit {
			fmt.Println("commit")
		}
	case "spec-blind":
		// The reason goes to stderr as `<detail>\t<what>`: the caller writes the
		// audit line from the first field and the message from the second.
		o := specblind.Options{Home: os.Getenv("HOME")}
		o.Cwd, _ = os.Getwd()
		args := os.Args[2:]
		for i := 0; i+1 < len(args); i += 2 {
			switch args[i] {
			case "--agent-type":
				o.AgentType = args[i+1]
			case "--tool":
				o.Tool = args[i+1]
			case "--file-path":
				o.FilePath = args[i+1]
			case "--command":
				o.Command = args[i+1]
			case "--project-dir":
				o.ProjectDir = args[i+1]
			case "--pipeline-dir":
				o.PipelineDir = args[i+1]
			case "--memory-dir":
				o.MemoryDir = args[i+1]
			}
		}
		if v := specblind.Judge(o); v.Blocked() {
			fmt.Fprintf(os.Stderr, "%s\t%s\n", v.Detail, v.What)
			os.Exit(2)
		}
	default:
		fmt.Fprintf(os.Stderr, "apd-guard: unknown guard %q\n", os.Args[1])
		os.Exit(64)
	}
}
