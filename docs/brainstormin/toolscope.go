package done

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"path"
	"sort"
	"strings"
)

// ---------------------------------------------------------------------------
// Tool-scope kanal
//
// Potpis nad promptom dokazuje samo sta je harness STAVIO u kontekst.
// Recenzent je agent sa alatima: ako ima Read, procitace spec tokom run-a,
// hash-chain ce i dalje savrseno validirati, a tvrdnja o izolaciji bice
// neistinita dok potpis kaze da je istinita.
//
// Tool scoping to SPROVODI u runtime-u ali ne ostavlja artefakt.
// Potpis BELEZI ulaz ali nista ne sprovodi.
// Dokaz nastaje tek kad potpis zabelezi ono sto je scoping sproveo -> ovaj fajl.
//
// ---------------------------------------------------------------------------
// Dve klase alata, dva matchera
//
// Prva verzija je imala jedan model: (Tool, Target) gde je Target putanja, i
// `strings.HasPrefix` kao autorizaciju. Pet izvrsenih sondi ga je oborilo
// (vidi toolscope_probe_test.go). Prefiks nije autorizacija:
//
//   - nad putanjom, jer bez kanonizacije `a/b/../../c` nije `a/c`;
//   - nad komandom, jer `git diff` kao prefiks pusta `git diff; cat spec`.
//
// Zato su alati podeljeni. Alat sa putanjom ide kroz permitPath (kanonizacija
// pa both-sides-slash poredjenje, isti idiom kao guard-scope posle v6.37.1).
// Alat cija je meta komandni string ide kroz permitCommand (segmentacija po
// granicama komande, isti pristup kao guard-bash-scope). Shell alat deklarisan
// kao path-alat je konfiguraciona greska i pada zatvoreno.
//
// Smer je svuda isti: sto se ne moze proveriti, ne prolazi.
// ---------------------------------------------------------------------------

const (
	domScope    = "apd.done.v1/tool-scope\x00"
	domCallInit = "apd.done.v1/tool-calls-init\x00"
	domCallStep = "apd.done.v1/tool-calls-step\x00"
)

// ShellRule opisuje alat cija meta NIJE putanja nego komandni string.
// AllowedCommands se poredi na poziciji komande svakog segmenta, ne kao
// slobodan prefiks celog stringa.
type ShellRule struct {
	Tool            string
	AllowedCommands []string
}

// ToolScope je grant koji je faza dobila. Prazan AllowedTools i nil Shell
// znace: nijedan alat.
type ToolScope struct {
	// Root je koren projekta. Potreban je da bi apsolutna meta mogla da se
	// dovede u odnos sa relativnim listama. Kad je prazan, apsolutna meta se
	// ne moze proveriti i zato se blokira.
	Root string

	AllowedTools        []string // alati cija je meta PUTANJA
	AllowedPathPrefixes []string // npr. [".apd/run/diff/"]
	DeniedPathPrefixes  []string // npr. [".apd/pipeline/spec-card.md", ".apd/pipeline/plan"]

	Shell *ShellRule // alat cija je meta KOMANDA; nil = shell nije dozvoljen
}

// ReviewerScope je preporuceni grant za dekontekstualizovanog recenzenta.
// Deny lista je redundantna uz allow listu i to je namerno: dva nezavisna
// uslova koja oba moraju da padnu da bi spec procurio.
func ReviewerScope(diffPrefix string, specPaths ...string) ToolScope {
	return ToolScope{
		AllowedTools:        []string{"read_diff"},
		AllowedPathPrefixes: []string{diffPrefix},
		DeniedPathPrefixes:  specPaths,
	}
}

// WithRoot vezuje grant za koren projekta. Bez njega apsolutne mete padaju.
func (s ToolScope) WithRoot(root string) ToolScope { s.Root = root; return s }

// WithShell dodaje shell alat sa eksplicitnom listom komandi.
// Recenzentu tipicno treba `git diff` i nista vise.
func (s ToolScope) WithShell(tool string, commands ...string) ToolScope {
	s.Shell = &ShellRule{Tool: tool, AllowedCommands: commands}
	return s
}

// ---------------------------------------------------------------------------
// Digest
// ---------------------------------------------------------------------------

// Digest je invarijantan na redosled listi: isti grant mora da da isti digest,
// inace korak 8 puca lazno na postenom run-u. Lazan BLOCK u enforcement lancu
// je skuplji od nezgodnosti -- rusi poverenje u sam mehanizam.
func (s ToolScope) Digest() Digest {
	var b bytes.Buffer
	b.WriteString(domScope)

	sorted := func(xs []string) []string {
		cp := append([]string(nil), xs...) // ne diraj pozivaocevu listu
		sort.Strings(cp)
		return cp
	}
	enc := func(tag uint16, xs []string) {
		var inner bytes.Buffer
		putTLVU32(&inner, 0x0001, uint32(len(xs)))
		for i, x := range sorted(xs) {
			putTLVU32(&inner, 0x0002, uint32(i))
			putTLVStr(&inner, 0x0003, x)
		}
		putTLV(&b, tag, inner.Bytes())
	}

	putTLVStr(&b, 0x000F, s.Root)
	enc(0x0010, s.AllowedTools)
	enc(0x0011, s.AllowedPathPrefixes)
	enc(0x0012, s.DeniedPathPrefixes)

	// shell grant ulazi u digest kao i sve ostalo -- inace bi se komandna
	// lista mogla naknadno prosiriti a digest ostati isti
	var sh bytes.Buffer
	if s.Shell != nil {
		putTLVStr(&sh, 0x0001, s.Shell.Tool)
		putTLVU32(&sh, 0x0002, uint32(len(s.Shell.AllowedCommands)))
		for i, c := range sorted(s.Shell.AllowedCommands) {
			putTLVU32(&sh, 0x0003, uint32(i))
			putTLVStr(&sh, 0x0004, c)
		}
	}
	putTLV(&b, 0x0013, sh.Bytes())

	return sha256.Sum256(b.Bytes())
}

// ---------------------------------------------------------------------------
// Kanonizacija putanja
// ---------------------------------------------------------------------------

// canonPath svodi metu na cistu, projekt-relativnu putanju.
//
// ok=false znaci "ne mogu da tvrdim gde ovo pokazuje" i uvek vodi u BLOCK.
// To pokriva praznu metu, apsolutnu metu bez deklarisanog korena, i svaku
// putanju koja posle Clean-a izlazi iz korena.
func (s ToolScope) canonPath(target string) (string, bool) {
	t := strings.TrimSpace(target)
	if t == "" {
		return "", false
	}
	t = strings.TrimPrefix(t, "./")

	if path.IsAbs(t) {
		if s.Root == "" {
			return "", false
		}
		root := strings.TrimSuffix(path.Clean(s.Root), "/")
		c := path.Clean(t)
		if c == root {
			return ".", true
		}
		if !strings.HasPrefix(c+"/", root+"/") {
			return "", false
		}
		return strings.TrimPrefix(c, root+"/"), true
	}

	c := path.Clean(t)
	if c == ".." || strings.HasPrefix(c, "../") {
		return "", false
	}
	return c, true
}

// canonPrefix svodi unos iz liste. Kad se ne moze relativizovati, ostaje
// leksicki ociscen: za deny to je dodatna provera, za allow znaci da nece
// matchovati relativnu metu -- oba u fail-closed smeru.
//
// ok=false za prazan unos. Bez toga bi Clean("") dao ".", sto je koren, pa bi
// jedan prazan string u allow listi otvorio ceo projekat.
func (s ToolScope) canonPrefix(entry string) (string, bool) {
	if strings.TrimSpace(entry) == "" {
		return "", false
	}
	if p, ok := s.canonPath(entry); ok {
		return p, true
	}
	return strings.TrimSuffix(path.Clean(strings.TrimSpace(entry)), "/"), true
}

// prefixMatch poredi po granici segmenta putanje, na obe strane.
// Bez slash-a s obe strane `src` matchuje `src-evil`, a unos koji je FAJL
// (a ne direktorijum) ne matchuje sam sebe -- oba buga su vec placena u
// guard-scope (v6.37.1).
func prefixMatch(subject, entry string) bool {
	e := strings.TrimSuffix(entry, "/")
	if e == "" || e == "." {
		return true // koren pokriva sve
	}
	return strings.HasPrefix(subject+"/", e+"/")
}

// ---------------------------------------------------------------------------
// Permits
// ---------------------------------------------------------------------------

// shellNames su alati cija meta nikad nije putanja. Ako se takav alat nadje u
// AllowedTools, grant je pogresno napisan i sve pada zatvoreno.
var shellNames = map[string]bool{
	"bash": true, "sh": true, "zsh": true, "shell": true,
	"Bash": true, "run_command": true, "execute_command": true, "terminal": true,
}

// Permits vraca gresku ako poziv izlazi iz grant-a.
func (s ToolScope) Permits(c ToolCall) error {
	if s.Shell != nil && s.Shell.Tool == c.Tool {
		return s.permitCommand(c.Target)
	}
	for _, t := range s.AllowedTools {
		if t != c.Tool {
			continue
		}
		if shellNames[t] {
			return fmt.Errorf("alat %q je shell i ne moze da se ogranici putanjom -- "+
				"deklarisi ga kroz ShellRule", t)
		}
		return s.permitPath(c.Target)
	}
	return fmt.Errorf("alat %q nije u scope-u", c.Tool)
}

func (s ToolScope) permitPath(target string) error {
	p, ok := s.canonPath(target)
	if !ok {
		return fmt.Errorf("meta %q se ne moze kanonizovati u odnosu na koren -- blokirano", target)
	}
	for _, d := range s.DeniedPathPrefixes {
		if e, ok := s.canonPrefix(d); ok && prefixMatch(p, e) {
			return fmt.Errorf("putanja %q je na deny listi (%s)", target, d)
		}
	}
	for _, a := range s.AllowedPathPrefixes {
		if e, ok := s.canonPrefix(a); ok && prefixMatch(p, e) {
			return nil
		}
	}
	return fmt.Errorf("putanja %q nije ni pod jednim dozvoljenim prefiksom", target)
}

// neanalizabilne konstrukcije: sadrzaj komande se odlucuje tek u runtime-u,
// pa staticka provera ne moze nista da tvrdi.
var opaqueShell = []string{"$(", "`", "${", "eval ", "exec ", "xargs "}

func (s ToolScope) permitCommand(cmd string) error {
	c := strings.TrimSpace(cmd)
	if c == "" {
		return errors.New("prazna komanda -- blokirano")
	}
	for _, bad := range opaqueShell {
		if strings.Contains(c, bad) {
			return fmt.Errorf("komanda sadrzi %q -- staticka provera nemoguca, blokirano", bad)
		}
	}
	// recenzent je read-only: svaka redirekcija je upis
	if strings.ContainsAny(c, "><") {
		return errors.New("redirekcija u komandi -- recenzent je read-only, blokirano")
	}

	// uslov 1: svaki segment mora da pocne dozvoljenom komandom
	rep := strings.NewReplacer("&&", "\n", "||", "\n", ";", "\n", "|", "\n", "&", "\n")
	for _, seg := range strings.Split(rep.Replace(c), "\n") {
		seg = strings.TrimSpace(seg)
		if seg == "" {
			continue
		}
		if !cmdAllowed(seg, s.Shell.AllowedCommands) {
			return fmt.Errorf("segment %q ne pocinje nijednom dozvoljenom komandom", seg)
		}
	}

	// uslov 2, nezavisan: nijedan token u komandi ne sme da pogodi deny listu
	for _, tok := range strings.Fields(c) {
		tok = strings.Trim(tok, `"'`)
		if !strings.Contains(tok, "/") && !strings.HasPrefix(tok, ".") {
			continue
		}
		p, ok := s.canonPath(tok)
		if !ok {
			continue // nije putanja koju umemo da svedemo; uslov 1 je vec prosao
		}
		for _, d := range s.DeniedPathPrefixes {
			if e, ok := s.canonPrefix(d); ok && prefixMatch(p, e) {
				return fmt.Errorf("komanda pominje deny putanju %q (%s)", tok, d)
			}
		}
	}
	return nil
}

// cmdAllowed trazi poklapanje na POZICIJI KOMANDE, sa granicom reci.
// `git diff` sme da pusti `git diff --stat`, ali ne i `git diffevil`.
func cmdAllowed(seg string, allowed []string) bool {
	for _, a := range allowed {
		a = strings.TrimSpace(a)
		if a == "" {
			continue
		}
		if seg == a {
			return true
		}
		if strings.HasPrefix(seg, a) {
			switch seg[len(a)] {
			case ' ', '\t':
				return true
			}
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Log poziva
// ---------------------------------------------------------------------------

// ToolCall je jedan presretnut poziv. Hooks su mesto emisije: oni vec presrecu
// sve pozive alata, pa je zapis potpun po konstrukciji, a ne po disciplini.
//
// Target je putanja za path-alate, a cela komanda za shell alat.
type ToolCall struct {
	Tool   string
	Target string
}

// ToolCallsChain vezuje ceo log poziva, po redu i po poziciji.
// Precutan poziv menja lanac isto kao precutan segment konteksta.
func ToolCallsChain(calls []ToolCall) Digest {
	h := sha256.Sum256([]byte(domCallInit))
	for i, c := range calls {
		var b bytes.Buffer
		b.WriteString(domCallStep)
		b.Write(h[:])
		putTLVU32(&b, 0x0001, uint32(i))
		putTLVStr(&b, 0x0002, c.Tool)
		putTLVStr(&b, 0x0003, c.Target)
		h = sha256.Sum256(b.Bytes())
	}
	return h
}

// Evidence je runtime dokaz koji ne staje u payload: pun log poziva i grant
// pod kojim su izvedeni. Payload nosi samo digeste.
type Evidence struct {
	ReviewerScope ToolScope
	ReviewerCalls []ToolCall
}

var (
	ErrNoEvidence     = errors.New("korak 8: nema tool-call evidence -- slepilo se ne moze dokazati")
	ErrScopeMismatch  = errors.New("korak 8: odobreni scope se ne poklapa sa reviewer_tool_scope_digest")
	ErrCallsMismatch  = errors.New("korak 8: log poziva se ne poklapa sa reviewer_tool_calls_digest")
	ErrOutOfScopeCall = errors.New("korak 8: IZOLACIJA PROBIJENA -- recenzent je sam dosao do zabranjenog izvora")
)
