// apd-guard — APD's guards that read shell commands, in one binary.
//
//	apd-guard bash-scope --project-dir <dir> --command <cmd> [--cwd <dir>] [--deny-all-writes] [scope ...]
//
// Exit 0 allows, exit 2 blocks (the reason goes to stderr). This is the judge
// only: it reads, it never writes.
package main

import (
	"fmt"
	"os"

	"github.com/zstevovich/claude-apd/guard/internal/bashscope"
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
			case "--deny-all-writes":
				o.DenyAllWrites = true
			default:
				o.Scope = append(o.Scope, args[i])
			}
		}
		rc, why := bashscope.Judge(o)
		if rc != 0 {
			fmt.Fprintln(os.Stderr, why)
		}
		os.Exit(rc)
	default:
		fmt.Fprintf(os.Stderr, "apd-guard: unknown guard %q\n", os.Args[1])
		os.Exit(64)
	}
}
