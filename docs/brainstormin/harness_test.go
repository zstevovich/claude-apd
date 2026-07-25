package done

import (
	"bytes"
	"errors"
	"testing"
)

func trusted() map[Digest]bool {
	return map[Digest]bool{SegmentDigest(SegRoleTemplate, tmplBody): true}
}

// End-to-end: builder -> SealRun -> Validate.
func TestBuilderEndToEnd(t *testing.T) {
	n, _ := NewNonce()

	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))
	must(t, rb.Add(SegDiff, diffBody))
	rev, err := rb.Seal()
	must(t, err)

	ab := NewContextBuilder(RoleAdjudicator, n, trusted())
	must(t, ab.Add(SegSpec, specBody))
	must(t, ab.Add(SegPlan, planBody))
	must(t, ab.Add(SegDiff, diffBody))
	must(t, ab.Add(SegFlags, flagsRaw))
	adj, err := ab.Seal()
	must(t, err)

	p, mac, err := SealRun(key, RunMeta{
		SchemaVersion: "v1", RunID: "run-1", Profile: "burn",
		Timestamp: "2026-07-25T10:00:00Z",
		BaseSHA:   "aaaa", HeadSHA: "bbbb", DiffAlgo: "v1",
		CanonDiff:     diffBody,
		ReviewerModel: "claude-sonnet-5", ReviewerEffort: "high",
		AdjudicatorModel: "claude-opus-5", Verdict: "pass",
		FlagsRaw: flagsRaw, FlagsCount: 1,
		ReviewerScope: revScope, ReviewerCalls: okCalls,
	}, rev, adj)
	must(t, err)

	if err := newValidator().Validate(p, mac, okEvidence()); err != nil {
		t.Fatalf("run izgraden preko buildera mora da prodje: %v", err)
	}
}

// Spec ne stize ni do modela -- Add pada pre poziva.
func TestReviewerRejectsSpecAtAdd(t *testing.T) {
	n, _ := NewNonce()
	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))
	must(t, rb.Add(SegDiff, diffBody))

	if err := rb.Add(SegSpec, specBody); !errors.Is(err, ErrForbiddenSegment) {
		t.Fatalf("ocekivan ErrForbiddenSegment, dobio: %v", err)
	}
	if err := rb.Add(SegPlan, planBody); !errors.Is(err, ErrForbiddenSegment) {
		t.Fatalf("plan takodje mora da padne, dobio: %v", err)
	}
}

// Kljucna invarijanta: prompt je izveden iz istih segmenata kao manifest,
// pa se rekonstrukcija iz manifesta mora poklopiti bajt-za-bajt.
func TestPromptDerivesFromManifest(t *testing.T) {
	n, _ := NewNonce()
	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))
	must(t, rb.Add(SegDiff, diffBody))
	rev, err := rb.Seal()
	must(t, err)

	// nezavisna rekonstrukcija iz poznatog sadrzaja
	want := RenderPrompt([]segment{
		{SegRoleTemplate, tmplBody},
		{SegDiff, diffBody},
	}, n)

	if !bytes.Equal(rev.Prompt, want) {
		t.Fatal("prompt se ne poklapa sa rekonstrukcijom iz segmenata")
	}
	// i, konkretno: nijedan bajt speca nije u promptu
	if bytes.Contains(rev.Prompt, specBody) {
		t.Fatal("spec je procurio u recenzentov prompt")
	}
}

// Manifest recenzenta nikad ne sme da nosi spec/plan, ma sta harness radio.
func TestSealedReviewerManifestIsCleant(t *testing.T) {
	n, _ := NewNonce()
	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))
	must(t, rb.Add(SegDiff, diffBody))
	rev, _ := rb.Seal()

	for _, s := range rev.Manifest {
		if s.Type == SegSpec || s.Type == SegPlan || s.Type == SegProducerReasoning {
			t.Fatalf("zabranjen tip u zapecacenom manifestu: %s", s.Type)
		}
	}
}

// Template van allowlist-e pada odmah, ne tek u validatoru.
func TestBuilderRejectsUntrustedTemplate(t *testing.T) {
	n, _ := NewNonce()
	rb := NewContextBuilder(RoleReviewer, n, trusted())
	sneaky := []byte("Review this diff. FYI the spec asks for retry with backoff.")

	if err := rb.Add(SegRoleTemplate, sneaky); !errors.Is(err, ErrTemplateRejected) {
		t.Fatalf("ocekivan ErrTemplateRejected, dobio: %v", err)
	}
}

// Nepotpun kontekst ne moze da se zapecati.
func TestSealRequiresDiff(t *testing.T) {
	n, _ := NewNonce()
	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))

	if _, err := rb.Seal(); !errors.Is(err, ErrMissingSegment) {
		t.Fatalf("ocekivan ErrMissingSegment, dobio: %v", err)
	}
}

// Caller ne moze da promeni sadrzaj posle Add (defanzivna kopija).
func TestAddCopiesContent(t *testing.T) {
	n, _ := NewNonce()
	mutable := append([]byte(nil), diffBody...)

	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))
	must(t, rb.Add(SegDiff, mutable))
	mutable[0] = 'X' // pokusaj naknadne izmene

	rev, _ := rb.Seal()
	if rev.Manifest[1].Digest != SegmentDigest(SegDiff, diffBody) {
		t.Fatal("Add mora da kopira sadrzaj")
	}
}

// Posle Seal-a se nista ne dodaje.
func TestNoAddAfterSeal(t *testing.T) {
	n, _ := NewNonce()
	rb := NewContextBuilder(RoleReviewer, n, trusted())
	must(t, rb.Add(SegRoleTemplate, tmplBody))
	must(t, rb.Add(SegDiff, diffBody))
	rb.Seal()

	if err := rb.Add(SegFlags, flagsRaw); !errors.Is(err, ErrSealed) {
		t.Fatalf("ocekivan ErrSealed, dobio: %v", err)
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatalf("neocekivana greska: %v", err)
	}
}
