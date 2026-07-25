package done

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
)

// ---------------------------------------------------------------------------
// Harness-side builder
//
// Poenta: prompt NIJE nezavisan buffer koji se pise paralelno sa manifestom.
// Prompt je cista funkcija segmenata -- RenderPrompt(segments). Zato ne postoji
// put da se u prompt ubaci bajt koji nije prosao kroz Add() i zavrsio u
// manifestu. Jedan izvor istine umesto dva koja se rucno drze u sinhronu.
//
// Sekundarno: zabranjen tip pada na Add(), dakle PRE poziva modela. Validator
// je post-hoc dokaz; builder je runtime prevencija.
// ---------------------------------------------------------------------------

type Role uint8

const (
	RoleReviewer    Role = 1 // dekontekstualizovan: samo framing + diff
	RoleAdjudicator Role = 2 // kontekstualizovan: sme spec i plan
)

func (r Role) String() string {
	if r == RoleReviewer {
		return "reviewer"
	}
	return "adjudicator"
}

var allowedByRole = map[Role]map[SegType]bool{
	RoleReviewer: reviewerAllowed,
	RoleAdjudicator: {
		SegRoleTemplate: true,
		SegSpec:         true,
		SegPlan:         true,
		SegDiff:         true,
		SegFlags:        true,
	},
}

// requiredByRole: sta manifest MORA da sadrzi da bi faza bila smislena.
var requiredByRole = map[Role][]SegType{
	RoleReviewer:    {SegRoleTemplate, SegDiff},
	RoleAdjudicator: {SegSpec, SegPlan, SegDiff, SegFlags},
}

var (
	ErrForbiddenSegment = errors.New("builder: tip segmenta nije dozvoljen za ovu ulogu")
	ErrDuplicateSegment = errors.New("builder: segment ovog tipa vec postoji")
	ErrMissingSegment   = errors.New("builder: nedostaje obavezan segment")
	ErrTemplateRejected = errors.New("builder: role template nije na allowlist-i")
	ErrSealed           = errors.New("builder: vec zapecacen, Add vise nije moguc")
)

// Nonce razdvaja segmente u promptu. Nasumican po run-u da sadrzaj ne moze da
// falsifikuje granicu segmenta (vidi napomenu kod RenderPrompt).
type Nonce [16]byte

func NewNonce() (Nonce, error) {
	var n Nonce
	_, err := rand.Read(n[:])
	return n, err
}

type segment struct {
	typ     SegType
	content []byte
}

type ContextBuilder struct {
	role             Role
	nonce            Nonce
	trustedTemplates map[Digest]bool
	segs             []segment
	seen             map[SegType]bool
	sealed           bool
}

func NewContextBuilder(role Role, nonce Nonce, trustedTemplates map[Digest]bool) *ContextBuilder {
	return &ContextBuilder{
		role:             role,
		nonce:            nonce,
		trustedTemplates: trustedTemplates,
		seen:             map[SegType]bool{},
	}
}

// Add je JEDINI ulaz u kontekst. Nema exported writer-a na prompt buffer.
func (b *ContextBuilder) Add(t SegType, content []byte) error {
	if b.sealed {
		return ErrSealed
	}
	if !allowedByRole[b.role][t] {
		return fmt.Errorf("%w: %s u ulozi %s", ErrForbiddenSegment, t, b.role)
	}
	if b.seen[t] {
		return fmt.Errorf("%w: %s", ErrDuplicateSegment, t)
	}
	if t == SegRoleTemplate && !b.trustedTemplates[SegmentDigest(SegRoleTemplate, content)] {
		return ErrTemplateRejected
	}
	cp := append([]byte(nil), content...) // defanzivna kopija: caller ne sme da menja posle Add
	b.segs = append(b.segs, segment{t, cp})
	b.seen[t] = true
	return nil
}

// Sealed je rezultat: prompt koji ide modelu i manifest koji ide u potpis,
// oba izvedena iz istog niza segmenata.
type Sealed struct {
	Role     Role
	Nonce    Nonce
	Prompt   []byte
	Manifest []Segment
	Chain    Digest
}

func (b *ContextBuilder) Seal() (*Sealed, error) {
	for _, t := range requiredByRole[b.role] {
		if !b.seen[t] {
			return nil, fmt.Errorf("%w: %s za ulogu %s", ErrMissingSegment, t, b.role)
		}
	}
	b.sealed = true

	manifest := make([]Segment, len(b.segs))
	for i, s := range b.segs {
		manifest[i] = Segment{Type: s.typ, Digest: SegmentDigest(s.typ, s.content)}
	}
	return &Sealed{
		Role:     b.role,
		Nonce:    b.nonce,
		Prompt:   RenderPrompt(b.segs, b.nonce),
		Manifest: manifest,
		Chain:    HashChain(manifest),
	}, nil
}

// RenderPrompt je deterministicka funkcija segmenata.
//
// Napomena o granicama: nonce sprecava da sadrzaj falsifikuje delimiter i tako
// navede model da procita jedan segment kao dva. To je pitanje percepcije
// modela, ne integriteta -- digest je tacan u oba slucaja. Nonce je zato
// mitigacija prompt-injection-a, a ne deo kriptografske garancije.
func RenderPrompt(segs []segment, n Nonce) []byte {
	h := hex.EncodeToString(n[:])
	var b bytes.Buffer
	for _, s := range segs {
		fmt.Fprintf(&b, "<<<APD:%s:%s>>>\n", h, s.typ)
		b.Write(s.content)
		if len(s.content) > 0 && s.content[len(s.content)-1] != '\n' {
			b.WriteByte('\n')
		}
		fmt.Fprintf(&b, "<<<APD:%s:/%s>>>\n", h, s.typ)
	}
	return b.Bytes()
}

// ---------------------------------------------------------------------------
// Pecacenje run-a
// ---------------------------------------------------------------------------

type RunMeta struct {
	SchemaVersion, RunID, Profile, Timestamp string
	BaseSHA, HeadSHA, DiffAlgo               string
	CanonDiff                                []byte
	ReviewerModel, ReviewerEffort            string
	AdjudicatorModel, Verdict                string
	FlagsRaw                                 []byte
	FlagsCount                               uint32

	// tool-scope kanal: grant pod kojim je recenzent radio i pun log poziva
	// koji su hooks presreli
	ReviewerScope ToolScope
	ReviewerCalls []ToolCall
}

// SealRun sklapa Payload iz vec zapecacenih konteksta. Digesti se ne prepisuju
// rucno -- vade se iz manifesta, pa ne mogu da se raziđu od onoga sto je model
// zaista dobio.
func SealRun(key []byte, m RunMeta, rev, adj *Sealed) (*Payload, []byte, error) {
	if rev.Role != RoleReviewer || adj.Role != RoleAdjudicator {
		return nil, nil, errors.New("SealRun: pogresne uloge")
	}
	dig := func(s *Sealed, t SegType) Digest {
		for _, seg := range s.Manifest {
			if seg.Type == t {
				return seg.Digest
			}
		}
		return Digest{}
	}
	p := &Payload{
		SchemaVersion: m.SchemaVersion, RunID: m.RunID,
		Profile: m.Profile, Timestamp: m.Timestamp,
		BaseSHA: m.BaseSHA, HeadSHA: m.HeadSHA, DiffAlgo: m.DiffAlgo,
		DiffDigest: DiffDigest(m.CanonDiff),

		ReviewerModel: m.ReviewerModel, ReviewerEffort: m.ReviewerEffort,
		ReviewerManifest:       rev.Manifest,
		ReviewerContextDigest:  rev.Chain,
		ReviewerTemplateDigest: dig(rev, SegRoleTemplate),
		FlagsDigest:            SegmentDigest(SegFlags, m.FlagsRaw),
		FlagsCount:             m.FlagsCount,

		ReviewerToolScopeDigest: m.ReviewerScope.Digest(),
		ReviewerToolCallsDigest: ToolCallsChain(m.ReviewerCalls),
		ReviewerToolCallsCount:  uint32(len(m.ReviewerCalls)),

		AdjudicatorModel:    m.AdjudicatorModel,
		AdjudicatorManifest: adj.Manifest,
		SpecDigest:          dig(adj, SegSpec),
		PlanDigest:          dig(adj, SegPlan),
		Verdict:             m.Verdict,
	}
	return p, Sign(key, p), nil
}
