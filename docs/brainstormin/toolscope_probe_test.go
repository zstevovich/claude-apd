package done

import "testing"

// ---------------------------------------------------------------------------
// Sonde nad ToolScope.Permits -- SVIH PET PADA na v3 referentnoj implementaciji.
//
// Ovo je crvena polovina. Svaka sonda je izvrsena, ne pretpostavljena.
// Kad se Permits popravi, sve prelaze u zeleno i ostaju kao regresija.
//
// Zajednicki koren A-C i E: `strings.HasPrefix` nad sirovim stringom.
// Prefiks nije autorizacija -- ni nad putanjom (nema kanonizacije) ni nad
// komandom (nema granice komande).
// ---------------------------------------------------------------------------

// A -- traversal probija deny.
// `.apd/run/diff/` je dozvoljen prefiks, deny gleda `.apd/pipeline/spec-card.md`,
// a `..` vodi na tacno taj fajl i ne matchuje nijedan deny prefiks.
// Ista klasa kao guard-scope bug iz v6.37.1: logicka vs fizicka putanja.
func TestTraversalEscapesDeny(t *testing.T) {
	s := ReviewerScope(".apd/run/diff/", ".apd/pipeline/spec-card.md", ".apd/pipeline/plan")
	c := ToolCall{"read_diff", ".apd/run/diff/../../pipeline/spec-card.md"}
	if err := s.Permits(c); err == nil {
		t.Fatal("PROBIJENO: traversal je prosao i allow i deny")
	}
}

// B -- prazan Target preskace obe liste putanja.
// `if c.Target == "" { return nil }` stoji PRE deny provere, pa je svaki poziv
// bez ekstrahovane putanje automatski dozvoljen. Fail-open na nepoznat oblik.
func TestEmptyTargetBypassesPaths(t *testing.T) {
	s := ReviewerScope(".apd/run/diff/", ".apd/pipeline/spec-card.md")
	if err := s.Permits(ToolCall{"read_diff", ""}); err == nil {
		t.Fatal("PROBIJENO: poziv bez targeta prolazi bez provere putanje")
	}
}

// C -- apsolutna putanja ne matchuje relativni deny prefiks.
// Isti fajl, druga notacija, deny ne vidi.
//
// Popravka trazi koren: bez njega se apsolutna i relativna notacija ne mogu
// dovesti u odnos, pa je jedini posten odgovor BLOCK. Sa korenom, mete se svode
// na isti oblik i deny radi. Obe grane su ovde.
func TestAbsolutePathEscapesDeny(t *testing.T) {
	bezKorena := ToolScope{
		AllowedTools:        []string{"read_file"},
		AllowedPathPrefixes: []string{"/proj/"},
		DeniedPathPrefixes:  []string{".apd/pipeline/spec-card.md"},
	}
	if err := bezKorena.Permits(ToolCall{"read_file", "/proj/.apd/pipeline/spec-card.md"}); err == nil {
		t.Fatal("PROBIJENO: apsolutna putanja zaobilazi relativni deny")
	}

	saKorenom := ToolScope{
		AllowedTools:        []string{"read_file"},
		AllowedPathPrefixes: []string{"."},
		DeniedPathPrefixes:  []string{".apd/pipeline/spec-card.md"},
	}.WithRoot("/proj")
	if err := saKorenom.Permits(ToolCall{"read_file", "/proj/src/x.go"}); err != nil {
		t.Fatalf("legitiman fajl pod korenom mora da prodje: %v", err)
	}
	if err := saKorenom.Permits(ToolCall{"read_file", "/proj/.apd/pipeline/spec-card.md"}); err == nil {
		t.Fatal("PROBIJENO: apsolutna notacija zaobilazi deny i kad je koren poznat")
	}
	if err := saKorenom.Permits(ToolCall{"read_file", "/etc/passwd"}); err == nil {
		t.Fatal("PROBIJENO: putanja van korena je prosla")
	}
}

// D -- digest scope-a zavisi od redosleda liste.
// Semanticki identican grant, drugi digest -> lazan ErrScopeMismatch u koraku 8.
// Lazno crveno u enforcement lancu je skuplje od nezgodnosti: rusi poverenje
// u sam mehanizam. Popravka: sortiraj pre enkodiranja.
func TestScopeDigestOrderSensitive(t *testing.T) {
	a := ToolScope{AllowedTools: []string{"read_diff", "grep"}}
	b := ToolScope{AllowedTools: []string{"grep", "read_diff"}}
	if a.Digest() != b.Digest() {
		t.Fatal("digest zavisi od redosleda liste -- isti grant, drugi digest")
	}
}

// E -- ONA KOJA RUSI MODEL, ne samo implementaciju.
//
// Realan APD adversarial recenzent nosi `tools: Read, Glob, Grep, Bash` i Bash
// mu je nuzan (`git diff`). Cim je Bash dozvoljen, Target je komandni string a
// ne putanja. Da bi legitiman poziv prosao, allow prefiks mora da pusti komandu
// -- a prefiks nad komandom je trivijalno probojan slozenom komandom.
//
// Prazna allow lista bi blokirala sve, ukljucujuci `git diff`: bash postaje
// neupotrebljiv. Nema podesavanja u kome je (Tool, Target) model ispravan za
// bash. APD ovo vec resava u guard-bash-scope regexom sidrenim na poziciju
// komande; referentna implementacija je regresija u odnosu na isporuceno.
func TestBashCompoundCommandEscapes(t *testing.T) {
	// Stara forma: shell u path-modelu. Nema podesavanja u kome je ispravna,
	// pa mora da padne zatvoreno umesto da tiho radi pogresnu proveru.
	uPathModelu := ToolScope{
		AllowedTools:        []string{"bash"},
		AllowedPathPrefixes: []string{"git diff"},
		DeniedPathPrefixes:  []string{".apd/pipeline/spec-card.md"},
	}
	if err := uPathModelu.Permits(ToolCall{"bash", "git diff"}); err == nil {
		t.Fatal("PROBIJENO: shell alat prihvacen u path-modelu")
	}

	// Ispravna forma: shell ima svoju listu komandi, poredjenu na poziciji
	// komande svakog segmenta.
	s := ToolScope{
		DeniedPathPrefixes: []string{".apd/pipeline/spec-card.md"},
	}.WithShell("bash", "git diff")

	if err := s.Permits(ToolCall{"bash", "git diff"}); err != nil {
		t.Fatalf("legitiman poziv mora da prodje: %v", err)
	}
	if err := s.Permits(ToolCall{"bash", "git diff --stat"}); err != nil {
		t.Fatalf("argumenti dozvoljene komande moraju da prodju: %v", err)
	}
	for _, leak := range []string{
		"git diff; cat .apd/pipeline/spec-card.md",
		"git diff && cat .apd/pipeline/spec-card.md",
		"git diff | cat .apd/pipeline/spec-card.md",
		"cat .apd/pipeline/spec-card.md",
		"git diff .apd/run/diff/../../pipeline/spec-card.md",
		"git diff $(cat .apd/pipeline/spec-card.md)",
		"git diffevil",
	} {
		if err := s.Permits(ToolCall{"bash", leak}); err == nil {
			t.Errorf("PROBIJENO komandom: %q", leak)
		}
	}
}
