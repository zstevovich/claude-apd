# Mutation check for the guard module: each entry removes or breaks ONE mechanism
# in a copy of the tree and expects `go test ./...` to fail there. An entry that
# no longer applies exactly once is reported, never skipped silently.
#
#   python3 guard/mutations.py <an empty work directory>
#
import sys,subprocess,shutil,os,re
S=sys.argv[1]; src=os.path.dirname(os.path.abspath(__file__))
muts=[
 ("state restored on Leave","internal/bashscope/judge.go","\tj.cwd, j.cwdUnknown, j.vn, j.vv, j.dirStack, j.group = sn.cwd, sn.unknown, sn.vn, sn.vv, sn.dirs, sn.group\n","\t_ = sn\n"),
 ("prefix assignment is not persistent","internal/bashscope/judge.go","\tpersistent := n == 0 || c.Decl != \"\"\n","\tpersistent := true\n"),
 ("env reaches the nested shell","internal/bashscope/judge.go","\tfor k := range j.envN { // what `X=v sh -c …` hands the nested shell\n\t\ttext = repl(text, j.envN[k], j.envV[k])\n","\tfor k := range j.envN {\n\t\t_ = k\n"),
 ("env reaches eval","internal/bashscope/judge.go","\tif text == \"\" {\n\t\treturn\n\t}\n\tfor k := range j.envN {\n\t\ttext = repl(text, j.envN[k], j.envV[k])\n","\tif text == \"\" {\n\t\treturn\n\t}\n\tfor k := range j.envN {\n\t\t_ = k\n"),
 ("eval runs in this shell","internal/bashscope/judge.go","\t\tj.evalHere(strings.Join(a, \" \"))\n","\t\tj.recurse(strings.Join(a, \" \"), false)\n"),
 ("Lost makes the state unknown","internal/bashscope/judge.go","\tj.cwdUnknown = true\n\tfor i := range j.vv {\n","\tfor i := range j.vv {\n"),
 ("env-variable form of the plugin root only when not assigned","internal/bashscope/judge.go","\t\tif _, set := j.assigned(v.name); set {\n\t\t\tcontinue\n\t\t}\n",""),
 ("env-variable form of the plugin root is exact","internal/bashscope/judge.go","if w == \"$\"+v.name+v.tail+t || w == \"${\"+v.name+\"}\"+v.tail+t {","if strings.Contains(w, v.name) && strings.HasSuffix(w, v.tail+t) {"),
 ("env-variable form of the plugin root accepted","internal/bashscope/judge.go","\t\t\tif w == \"$\"+v.name+v.tail+t || w == \"${\"+v.name+\"}\"+v.tail+t {\n\t\t\t\treturn true\n","\t\t\tif w == \"$\"+v.name+v.tail+t || w == \"${\"+v.name+\"}\"+v.tail+t {\n\t\t\t\tcontinue\n"),
 ("apd tool anchored to the plugin root","internal/bashscope/judge.go","\t\t\tif p == j.c.apdRoot+\"/bin/core/\"+t {\n","\t\t\tif strings.HasSuffix(p, \"/plugins/apd/bin/core/\"+t) {\n"),
 ("apd exemption exists","internal/bashscope/judge.go","\t\tif t.apd || t.abs == \"\" {\n","\t\tif t.abs == \"\" {\n"),
 ("read forgets the variable","internal/bashscope/judge.go","\t\tforget(tools.Positionals(a, `^-[adinNptu]$`)...)\n","\n"),
 ("append to an unknown value is unknown","internal/bashscope/judge.go","\t\tif !ok {\n\t\t\treturn unknownValue\n\t\t}\n","\t\t_ = ok\n"),
 ("array value is unknown","internal/bashscope/judge.go","\tif a.Opaque {\n\t\treturn unknownValue\n\t}\n",""),
 (">& file is a write","internal/shell/walk.go","\t\t\tif t := w.word(r.Word); !fdOnly(t) {\n","\t\t\tif t := w.word(r.Word); false && !fdOnly(t) {\n"),
 ("<> file is a write","internal/shell/walk.go","syntax.AppAll, syntax.ClbOut, syntax.RdrInOut:","syntax.AppAll, syntax.ClbOut:"),
 ("pipeline elements isolated","internal/shell/walk.go","\t\t\tw.scoped(PipeElement, func() { w.stmt(x.X, \"\") })\n\t\t\tw.scoped(PipeElement, func() { w.stmt(x.Y, body) })\n","\t\t\tw.stmt(x.X, \"\")\n\t\t\tw.stmt(x.Y, body)\n"),
 ("background isolated","internal/shell/walk.go","\tcase s.Background || s.Coprocess:\n\t\tw.scoped(Background, func() { w.stmt1(s, fed) })\n","\tcase s.Background || s.Coprocess:\n\t\tw.stmt1(s, fed)\n"),
 ("heredoc piped into a shell","internal/shell/walk.go","\t\t\tif readsStdin(x.Y) {\n","\t\t\tif false {\n"),
 ("function call replays the body","internal/shell/walk.go","\t\t\t(&walker{Reader: w.Reader, src: f.src, v: w.v, cond: w.cond}).stmt(f.body, \"\")\n","\t\t\t_ = f\n"),
 ("function call by the decoded name","internal/shell/walk.go","\t\t\tf, called = w.funcs[c.Words[0]]\n","\t\t\tf, called = w.funcs[x.Args[0].Lit()]\n"),
 ("a maybe-defined function does not shadow","internal/shell/walk.go","\t\tc.Function = called && !f.maybe\n","\t\tc.Function = called\n"),
 ("a maybe-defined function leaves the state unknown","internal/shell/walk.go","\t\t\t\tw.v.Lost(\"a function that may not have been defined\")\n","\n"),
 ("the right side of && may not run","internal/shell/walk.go","\t\t\tw.maybeRun(func() { w.stmt(x.Y, \"\") }) // the right side of && / || may not run\n","\t\t\tw.stmt(x.Y, \"\")\n"),
 ("a branch may not run","internal/shell/walk.go","\t\t\tw.maybeRun(func() { w.stmts(cl.Then) })\n","\t\t\tw.stmts(cl.Then)\n"),
 ("unset behind command/builtin","internal/shell/walk.go","\t\t\tfor k < len(c.Words) && (c.Words[k] == \"command\" || c.Words[k] == \"builtin\") {\n\t\t\t\tk++\n\t\t\t}\n",""),
 ("call budget ends in Lost","internal/shell/walk.go","\t\t\tw.v.Lost(\"more function calls than the reader follows\")\n","\n"),
 ("function registered after its definition is read","internal/shell/walk.go","\t\tw.scoped(FuncBody, func() { w.stmt(x.Body, \"\") })\n\t\tw.funcs[x.Name.Value] = fn{x.Body, w.src, w.cond > 0}\n","\t\tw.funcs[x.Name.Value] = fn{x.Body, w.src, w.cond > 0}\n\t\tw.scoped(FuncBody, func() { w.stmt(x.Body, \"\") })\n"),
 ("function definitions stay inside their scope","internal/shell/walk.go","\tw.v.Leave(s)\n\tw.Reader.funcs = saved\n","\tw.v.Leave(s)\n\t_ = saved\n"),
 ("unset -f removes the function","internal/shell/walk.go","\t\t\tdelete(w.funcs, x) // not followed","\t\t\t_ = x // not followed"),
 ("plain unset of a function name loses the state","internal/shell/walk.go","\t\t\t\tw.v.Lost(\"unset of a name that is a function\")\n","\n"),
 ("a function shadows the builtin of its name","internal/bashscope/judge.go","\tif n == 0 || c.Function {\n","\tif n == 0 {\n"),
 ("call prefix in effect for the body","internal/bashscope/judge.go","\t\tj.setvar(a.Name, j.valueOf(a))\n\t}\n\tj.frames = append(j.frames, fr)\n","\t}\n\tj.frames = append(j.frames, fr)\n"),
 ("after a prefixed call the variable is unknown","internal/bashscope/judge.go","\t\tj.setvar(fr[i].name, unknownValue)\n","\t\t_ = i\n"),
 ("a tool's unknown write is refused","internal/bashscope/judge.go","\t\t\t\tif t.Unknown != \"\" {\n\t\t\t\t\tj.addUnknown(t.Unknown)\n\t\t\t\t} else {","\t\t\t\tif t.Unknown != \"\" {\n\t\t\t\t} else {"),
 ("curl config file","internal/tools/tools.go","\tif o.flags[\"-K\"] || o.flags[\"--config\"] {\n\t\tout = append(out, unknown+\"curl","\tif false {\n\t\tout = append(out, unknown+\"curl"),
 ("wget -e","internal/tools/tools.go","\tif o.flags[\"-e\"] || o.flags[\"--execute\"] || o.flags[\"--config\"] {","\tif false {"),
 ("curl -o relative to --output-dir","internal/tools/tools.go","\t\tcase dir != \"\" && !strings.HasPrefix(v, \"/\"):\n","\t\tcase false:\n"),
 ("rsync directories are taken from the destination","internal/tools/tools.go","\t\t\tout = append(out, strings.TrimSuffix(dest, \"/\")+\"/\"+d)\n","\t\t\tout = append(out, d)\n"),
 ("rsync writing options","internal/tools/tools.go","\tfor _, d := range o.all(\"--backup-dir\", \"--temp-dir\", \"-T\", \"--partial-dir\") {","\tfor _, d := range o.all() {"),
 ("curl --output-dir with --next","internal/tools/tools.go","\tif dir != \"\" && (o.flags[\"--next\"] || o.flags[\"-:\"]) {","\tif false {"),
 ("a conditional unset keeps the function as maybe","internal/shell/walk.go","\t\t\tif fOnly && w.cond > 0 {","\t\t\tif false {"),
 ("tilde follows HOME set in the command","internal/bashscope/judge.go","\tif h, ok := j.assigned(\"HOME\"); ok {\n\t\treturn h + s[1:]\n\t}\n",""),
 ("cd with no operand follows HOME set in the command","internal/bashscope/judge.go","\t\t\tif _, moved := j.assigned(\"HOME\"); moved {","\t\t\tif false {"),
 ("curl/wget start-up file moved, persistent","internal/bashscope/judge.go","\t\tif _, ok := j.assigned(n); ok {\n\t\t\treturn true\n\t\t}\n\t\tfor _, e := range j.envN {","\t\tfor _, e := range j.envN {"),
 ("curl/wget start-up file moved, prefix","internal/bashscope/judge.go","\t\t\tif e == n {\n\t\t\t\treturn true\n\t\t\t}\n","\t\t\t_ = e\n"),
 ('assignment through command/builtin lasts','internal/bashscope/judge.go','\t\t\t\tj.setvar(x[:k], j.subst(x[k+1:]))\n\t\t\t}\n\t\t}\n\tcase "eval":','\t\t\t\t_ = k\n\t\t\t}\n\t\t}\n\tcase "eval":'),
 ('bundled short option takes a value','internal/tools/tools.go','\t\t\t\tif strings.Contains(short, c) {\n','\t\t\t\tif len(x) == 2 && strings.Contains(short, c) {\n'),
 ('glued short option value','internal/tools/tools.go','\t\t\t\t\tv := x[k+1:]\n\t\t\t\t\tif v == "" {','\t\t\t\t\tv := ""\n\t\t\t\t\tif v == "" {'),
 ('long option with =','internal/tools/tools.go','\t\t\tif eq {\n\t\t\t\to.val["--"+name] = append(o.val["--"+name], v)\n','\t\t\tif eq {\n\t\t\t\t_ = v\n'),
 ('-- ends the options','internal/tools/tools.go','\t\tcase x == "--":\n\t\t\to.pos = append(o.pos, a[i+1:]...)\n\t\t\treturn o\n',''),
 ('curl -O writes into the working directory','internal/tools/tools.go','\t\tif dir == "" {\n\t\t\tdir = "./"\n\t\t}\n\t\tout = append(out, dir)\n','\t\tif dir != "" {\n\t\t\tout = append(out, dir)\n\t\t}\n'),
 ('stdout is not a file','internal/tools/tools.go','\t\tswitch {\n\t\tcase v == "-":\n','\t\tswitch {\n\t\tcase false:\n'),
 ('wget saves into the working directory','internal/tools/tools.go','\t\t} else {\n\t\t\tout = append(out, "./")\n\t\t}\n\t}\n\treturn out, true\n}\n\nfunc sortOut','\t\t}\n\t}\n\treturn out, true\n}\n\nfunc sortOut'),
 ('tar old-style bundle','internal/tools/tools.go','\tif len(a) > 0 && !strings.HasPrefix(a[0], "-") {\n','\tif false {\n'),
 ('tar old-style valued letters take arguments in order','internal/tools/tools.go','\t\t\tif strings.Contains(valued, c) && len(rest) > 0 {\n','\t\t\tif false {\n'),
 ('tar creating an archive writes it','internal/tools/tools.go','\t\tif f := o.last("-f", "--file"); f != "" && f != "-" {\n\t\t\treturn []string{f}, true\n\t\t}\n',''),
 ('unzip listing writes nothing','internal/tools/tools.go','\t\treturn nil, false // list, test, to stdout\n','\n'),
 ("find's own output files",'internal/tools/tools.go',"\t\t\tout = append(out, at(a, k+1)) // find's own output files\n",'\n'),
 ('cp -t names the destination','internal/tools/tools.go','\tif d := o.last("-t", "--target-directory"); d != "" {\n\t\treturn []string{d}, true\n\t}\n\tif len(o.pos) == 0 {','\tif len(o.pos) == 0 {'),
 ('mv counts its source','internal/tools/tools.go','\treturn append(o.pos, o.all("-t", "--target-directory")...), true','\treturn append(o.pos[len(o.pos)-1:], o.all("-t", "--target-directory")...), true'),
 ('rm does not follow the link','internal/tools/tools.go','\tnofollow := cmd == "rm" || cmd == "rmdir" || cmd == "unlink"\n','\tnofollow := false\n'),
 ('xargs with a writer is unknown','internal/bashscope/judge.go','\t\t\t\tj.addUnknown("xargs " + x)\n','\t\t\t\t_ = x\n'),
 ('ANSI-C decoded','internal/shell/walk.go','\t\t\tif x.Dollar {\n\t\t\t\tb.WriteString(ansiC(x.Value))\n','\t\t\tif x.Dollar {\n\t\t\t\tb.WriteString(x.Value)\n'),
 ('ANSI-C short octal','internal/shell/walk.go','\t\t\tv, n := digits(i+1, 3, 8)\n','\t\t\tv, n := digits(i+1, 0, 8)\n'),
 ('substitution inside (( )) is read','internal/shell/walk.go','\t\tw.inner(s.Cmd)\n\t\ttail()\n','\t\ttail()\n'),
 ('function body isolated at definition','internal/shell/walk.go','\t\tw.scoped(FuncBody, func() { w.stmt(x.Body, "") })\n','\t\tw.stmt(x.Body, "")\n'),
 ('scratchpad exact layout','internal/paths/paths.go','claude-[0-9]+/[^/]+/[^/]+/scratchpad','claude-[0-9]+.*/scratchpad'),
 ('dangling symlink followed','internal/paths/paths.go','\tif abs == "" && !nofollow && IsLink(p) {','\tif false && abs == "" && !nofollow && IsLink(p) {'),
 ('last-component symlink followed','internal/paths/paths.go','\tif !nofollow && IsLink(abs) {\n\t\treturn e.CanonAbs(abs, "/", false)\n\t}\n',''),
]
ok=0
for name,f,old,new in muts:
    d=S+"/mutwork"; shutil.rmtree(d,ignore_errors=True); shutil.copytree(src,d)
    p=d+"/"+f; s=open(p).read()
    if s.count(old)!=1: print("DID NOT APPLY (%d): %s"%(s.count(old),name)); continue
    open(p,"w").write(s.replace(old,new))
    r=subprocess.run(["go","test","./..."],cwd=d,capture_output=True,text=True)
    out=r.stdout+r.stderr
    fails=len(re.findall(r"^\s+\S+_test\.go:\d+:",out,re.M))
    if "build failed" in out or "[build failed]" in out or "vet:" in out: print("BUILD BROKE:",name,out[-300:]); continue
    if r.returncode==0: print("NOT CAUGHT:",name)
    else: ok+=1; print("caught (%d rows): %s"%(fails,name))
shutil.rmtree(S+"/mutwork",ignore_errors=True)
print(ok,"/",len(muts))
assert len(muts)>=70, 'the mutation list shrank'
