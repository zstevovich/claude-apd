package done

import (
	"errors"
	"testing"
)

var (
	key      = []byte("test-hmac-key")
	specBody = []byte("SPEC: dodaj retry sa exponential backoff")
	planBody = []byte("PLAN: 1) wrap client 2) test")
	tmplBody = []byte("You review a diff. You have no spec. Find defects.")
	diffBody = []byte("--- a/x.go\n+++ b/x.go\n@@\n+func retry() {}\n")
	flagsRaw = []byte("[{id:1,note:\"unbounded retry\"}]")
)

func fakeBuilder(base, head, algo string) ([]byte, error) { return diffBody, nil }

func newValidator() *Validator {
	return &Validator{
		Key:              key,
		TrustedTemplates: map[Digest]bool{SegmentDigest(SegRoleTemplate, tmplBody): true},
		BuildDiff:        fakeBuilder,
	}
}

// honest gradi validan zapis, pa ga testovi pojedinacno kvare.
func honest() *Payload {
	rev := []Segment{
		{SegRoleTemplate, SegmentDigest(SegRoleTemplate, tmplBody)},
		{SegDiff, SegmentDigest(SegDiff, diffBody)},
	}
	adj := []Segment{
		{SegSpec, SegmentDigest(SegSpec, specBody)},
		{SegPlan, SegmentDigest(SegPlan, planBody)},
		{SegDiff, SegmentDigest(SegDiff, diffBody)},
		{SegFlags, SegmentDigest(SegFlags, flagsRaw)},
	}
	return &Payload{
		SchemaVersion: "v1", RunID: "run-42", Profile: "burn",
		Timestamp: "2026-07-25T10:00:00Z",
		BaseSHA:   "aaaa", HeadSHA: "bbbb", DiffAlgo: "v1",
		DiffDigest: DiffDigest(diffBody),

		ReviewerModel: "claude-sonnet-5", ReviewerEffort: "high",
		ReviewerManifest:       rev,
		ReviewerContextDigest:  HashChain(rev),
		ReviewerTemplateDigest: SegmentDigest(SegRoleTemplate, tmplBody),
		FlagsDigest:            SegmentDigest(SegFlags, flagsRaw),
		FlagsCount:             1,

		ReviewerToolScopeDigest: revScope.Digest(),
		ReviewerToolCallsDigest: ToolCallsChain(okCalls),
		ReviewerToolCallsCount:  uint32(len(okCalls)),

		AdjudicatorModel:    "claude-opus-5",
		AdjudicatorManifest: adj,
		SpecDigest:          SegmentDigest(SegSpec, specBody),
		PlanDigest:          SegmentDigest(SegPlan, planBody),
		Verdict:             "pass",
	}
}

func TestHonestRunValidates(t *testing.T) {
	p := honest()
	if err := newValidator().Validate(p, Sign(key, p), okEvidence()); err != nil {
		t.Fatalf("posten run mora da prodje, dobio: %v", err)
	}
}

// Napad 1: spec ubacen recenzentu i posteno prijavljen u manifestu.
// Korak 4 ga hvata.
func TestSpecLeakDeclared(t *testing.T) {
	p := honest()
	p.ReviewerManifest = append(p.ReviewerManifest,
		Segment{SegSpec, SegmentDigest(SegSpec, specBody)})
	p.ReviewerContextDigest = HashChain(p.ReviewerManifest)

	err := newValidator().Validate(p, Sign(key, p), okEvidence())
	if !errors.Is(err, ErrContextLeak) {
		t.Fatalf("ocekivan ErrContextLeak, dobio: %v", err)
	}
}

// Napad 2: spec predat recenzentu ali PRECUTAN u manifestu.
// Korak 3 ga hvata -- lanac ide preko svih stvarnih ulaza.
func TestSpecLeakHidden(t *testing.T) {
	p := honest()
	actual := append([]Segment{}, p.ReviewerManifest...)
	actual = append(actual, Segment{SegSpec, SegmentDigest(SegSpec, specBody)})

	// harness racuna digest nad stvarnim ulazom, manifest laze da speca nema
	p.ReviewerContextDigest = HashChain(actual)

	err := newValidator().Validate(p, Sign(key, p), okEvidence())
	if !errors.Is(err, ErrChainMismatch) {
		t.Fatalf("ocekivan ErrChainMismatch, dobio: %v", err)
	}
}

// Napad 3: spec zamaskiran kao DIFF segment.
// Korak 5 ga hvata -- digest ne odgovara rekonstruisanom diffu.
func TestSpecDisguisedAsDiff(t *testing.T) {
	p := honest()
	p.ReviewerManifest = []Segment{
		{SegRoleTemplate, SegmentDigest(SegRoleTemplate, tmplBody)},
		{SegDiff, SegmentDigest(SegDiff, append(append([]byte{}, diffBody...), specBody...))},
	}
	p.ReviewerContextDigest = HashChain(p.ReviewerManifest)

	err := newValidator().Validate(p, Sign(key, p), okEvidence())
	if !errors.Is(err, ErrDiffSegment) {
		t.Fatalf("ocekivan ErrDiffSegment, dobio: %v", err)
	}
}

// Napad 4: template koji usmeno prepricava spec umesto da samo daje framing.
// Korak 6 ga hvata.
func TestUntrustedTemplate(t *testing.T) {
	p := honest()
	sneaky := []byte("You review a diff. FYI the spec says: add retry with backoff.")
	p.ReviewerTemplateDigest = SegmentDigest(SegRoleTemplate, sneaky)
	p.ReviewerManifest[0] = Segment{SegRoleTemplate, p.ReviewerTemplateDigest}
	p.ReviewerContextDigest = HashChain(p.ReviewerManifest)

	err := newValidator().Validate(p, Sign(key, p), okEvidence())
	if !errors.Is(err, ErrTemplateUntruted) {
		t.Fatalf("ocekivan ErrTemplateUntruted, dobio: %v", err)
	}
}

// Napad 5: adjudikator presudio nad drugim diffom nego sto je recenziran.
func TestAdjudicatorDifferentDiff(t *testing.T) {
	p := honest()
	p.AdjudicatorManifest[2] = Segment{SegDiff, SegmentDigest(SegDiff, []byte("neki drugi diff"))}

	err := newValidator().Validate(p, Sign(key, p), okEvidence())
	if !errors.Is(err, ErrAdjContext) {
		t.Fatalf("ocekivan ErrAdjContext, dobio: %v", err)
	}
}

// Napad 6: neko menja verdikt posle potpisivanja.
func TestTamperedVerdict(t *testing.T) {
	p := honest()
	mac := Sign(key, p)
	p.Verdict = "pass-forced"

	if err := newValidator().Validate(p, mac, okEvidence()); !errors.Is(err, ErrMAC) {
		t.Fatalf("ocekivan ErrMAC, dobio: %v", err)
	}
}

// Reordering segmenata mora da promeni lanac (pozicija je vezana).
func TestChainIsOrderSensitive(t *testing.T) {
	a := []Segment{
		{SegRoleTemplate, SegmentDigest(SegRoleTemplate, tmplBody)},
		{SegDiff, SegmentDigest(SegDiff, diffBody)},
	}
	b := []Segment{a[1], a[0]}
	if HashChain(a) == HashChain(b) {
		t.Fatal("lanac mora da bude osetljiv na redosled")
	}
}

// Isti sadrzaj pod razlicitim tipom mora da da razlicit digest.
func TestTypeBoundToContent(t *testing.T) {
	if SegmentDigest(SegSpec, diffBody) == SegmentDigest(SegDiff, diffBody) {
		t.Fatal("tip mora da ulazi u segment digest")
	}
}

// ---------------------------------------------------------------------------
// Korak 8: tool kanal
// ---------------------------------------------------------------------------

var revScope = ReviewerScope(".apd/run/diff/", ".apd/pipeline/spec-card.md", ".apd/pipeline/plan")

var okCalls = []ToolCall{
	{"read_diff", ".apd/run/diff/x.go.patch"},
}

func okEvidence() *Evidence {
	return &Evidence{ReviewerScope: revScope, ReviewerCalls: okCalls}
}

// Napad 7: recenzent je sam procitao spec tokom run-a.
// Prompt je bio cist, koraci 3-6 prolaze, hvata ga tek korak 8.
func TestReviewerReadSpecItself(t *testing.T) {
	p := honest()
	calls := append(append([]ToolCall{}, okCalls...),
		ToolCall{"read_file", ".apd/pipeline/spec-card.md"})

	p.ReviewerToolCallsDigest = ToolCallsChain(calls)
	p.ReviewerToolCallsCount = uint32(len(calls))

	ev := &Evidence{ReviewerScope: revScope, ReviewerCalls: calls}
	err := newValidator().Validate(p, Sign(key, p), ev)
	if !errors.Is(err, ErrOutOfScopeCall) {
		t.Fatalf("ocekivan ErrOutOfScopeCall, dobio: %v", err)
	}
}

// Napad 8: poziv van scope-a precutan u logu.
func TestHiddenToolCall(t *testing.T) {
	p := honest() // digest tvrdi da je bio samo okCalls
	actual := append(append([]ToolCall{}, okCalls...),
		ToolCall{"read_file", ".apd/pipeline/spec-card.md"})

	ev := &Evidence{ReviewerScope: revScope, ReviewerCalls: actual}
	if err := newValidator().Validate(p, Sign(key, p), ev); !errors.Is(err, ErrCallsMismatch) {
		t.Fatalf("ocekivan ErrCallsMismatch, dobio: %v", err)
	}
}

// Napad 9: scope naknadno prosiren da bi poziv izgledao dozvoljeno.
func TestWidenedScope(t *testing.T) {
	p := honest()
	wide := revScope
	wide.AllowedPathPrefixes = append(wide.AllowedPathPrefixes, ".apd/pipeline/")

	ev := &Evidence{ReviewerScope: wide, ReviewerCalls: okCalls}
	if err := newValidator().Validate(p, Sign(key, p), ev); !errors.Is(err, ErrScopeMismatch) {
		t.Fatalf("ocekivan ErrScopeMismatch, dobio: %v", err)
	}
}

// Bez evidence slepilo je tvrdnja, ne dokaz.
func TestEvidenceRequired(t *testing.T) {
	p := honest()
	if err := newValidator().Validate(p, Sign(key, p), nil); !errors.Is(err, ErrNoEvidence) {
		t.Fatalf("ocekivan ErrNoEvidence, dobio: %v", err)
	}
}

// Deny lista drzi i kad bi allow lista propustila (dva nezavisna uslova).
func TestDenyBeatsAllow(t *testing.T) {
	s := ToolScope{
		AllowedTools:        []string{"read_file"},
		AllowedPathPrefixes: []string{".apd/"},
		DeniedPathPrefixes:  []string{".apd/pipeline/spec-card.md"},
	}
	if err := s.Permits(ToolCall{"read_file", ".apd/pipeline/spec-card.md"}); err == nil {
		t.Fatal("deny lista mora da nadjaca allow prefiks")
	}
}
