// Package done implementira TLV-serijalizovan, HMAC-potpisan .done zapis za
// APD pipeline run, sa verifikabilnim dokazom da je adversarial recenzent
// radio dekontekstualizovano (samo diff, bez spec-a i plana).
//
// Trust boundary: HMAC kljuc je koren poverenja. Ovaj paket daje
// tamper-evidence i post-hoc auditabilnost protiv svega osim kompromitovanog
// potpisnika. Ne daje kriptografsku nemogucnost curenja konteksta.
package done

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
)

// ---------------------------------------------------------------------------
// Domain separation
//
// Svaki hash ima svoj prefiks da digest iz jednog konteksta nikad ne moze da
// se reinterpretira kao digest iz drugog (npr. segment digest kao diff digest).
// ---------------------------------------------------------------------------

const (
	domSegment   = "apd.done.v1/segment\x00"
	domChainInit = "apd.done.v1/chain-init\x00"
	domChainStep = "apd.done.v1/chain-step\x00"
	domDiff      = "apd.done.v1/diff\x00"
	domPayload   = "apd.done.v1/payload\x00"
)

// ---------------------------------------------------------------------------
// TLV
//
// tag: uint16 BE, len: uint32 BE, value: raw bytes.
// Length-prefix svuda -> nema dvosmislenosti oko granica polja, pa nema
// canonical-JSON klase napada (whitespace, redosled kljuceva, duplikati,
// unicode escape varijante).
// ---------------------------------------------------------------------------

func putTLV(b *bytes.Buffer, tag uint16, val []byte) {
	var hdr [6]byte
	binary.BigEndian.PutUint16(hdr[0:2], tag)
	binary.BigEndian.PutUint32(hdr[2:6], uint32(len(val)))
	b.Write(hdr[:])
	b.Write(val)
}

func putTLVStr(b *bytes.Buffer, tag uint16, s string) { putTLV(b, tag, []byte(s)) }
func putTLVU32(b *bytes.Buffer, tag uint16, v uint32) {
	var x [4]byte
	binary.BigEndian.PutUint32(x[:], v)
	putTLV(b, tag, x[:])
}
func putTLVDig(b *bytes.Buffer, tag uint16, d Digest) { putTLV(b, tag, d[:]) }

// ---------------------------------------------------------------------------
// Tipovi segmenata konteksta
// ---------------------------------------------------------------------------

type SegType uint8

const (
	SegRoleTemplate      SegType = 1 // challenger framing template
	SegDiff              SegType = 2 // kanonizovan unified diff
	SegSpec              SegType = 3 // specifikacija  -- ZABRANJEN recenzentu
	SegPlan              SegType = 4 // plan implementacije -- ZABRANJEN recenzentu
	SegProducerReasoning SegType = 5 // producer reasoning  -- ZABRANJEN recenzentu
	SegFlags             SegType = 6 // izlaz recenzenta (ulaz adjudikatora)
)

func (t SegType) String() string {
	switch t {
	case SegRoleTemplate:
		return "ROLE_TEMPLATE"
	case SegDiff:
		return "DIFF"
	case SegSpec:
		return "SPEC"
	case SegPlan:
		return "PLAN"
	case SegProducerReasoning:
		return "PRODUCER_REASONING"
	case SegFlags:
		return "FLAGS"
	}
	return fmt.Sprintf("UNKNOWN(%d)", uint8(t))
}

// reviewerAllowed je celo srce izolacije: sve sto nije ovde, ne sme da postoji
// u recenzentovom manifestu.
var reviewerAllowed = map[SegType]bool{
	SegRoleTemplate: true,
	SegDiff:         true,
}

type Digest [32]byte

// Segment je zabelezen ulaz predat modelu. Sadrzaj se ne mora cuvati -- digest
// je dovoljan, jer se DIFF segment nezavisno rekonstruise iz gita.
type Segment struct {
	Type   SegType
	Digest Digest
}

// SegmentDigest vezuje tip za sadrzaj. Bez ovoga bi se SPEC segment mogao
// preimenovati u DIFF uz isti digest.
func SegmentDigest(t SegType, content []byte) Digest {
	var b bytes.Buffer
	b.WriteString(domSegment)
	putTLV(&b, 0x0001, []byte{byte(t)})
	putTLV(&b, 0x0002, content)
	return sha256.Sum256(b.Bytes())
}

// DiffDigest je zaseban domen od SegmentDigest namerno.
func DiffDigest(canonDiff []byte) Digest {
	var b bytes.Buffer
	b.WriteString(domDiff)
	putTLV(&b, 0x0001, canonDiff)
	return sha256.Sum256(b.Bytes())
}

// HashChain vezuje ceo niz segmenata, po redu i po poziciji.
//
// Ovo je razlog zasto sakriveni segment slomi potpis: lanac ide preko SVIH
// segmenata, pa svaki neprijavljen ulaz menja krajnji digest.
func HashChain(segs []Segment) Digest {
	h := sha256.Sum256([]byte(domChainInit))
	for i, s := range segs {
		var b bytes.Buffer
		b.WriteString(domChainStep)
		b.Write(h[:])
		putTLVU32(&b, 0x0001, uint32(i))
		putTLV(&b, 0x0002, []byte{byte(s.Type)})
		putTLVDig(&b, 0x0003, s.Digest)
		h = sha256.Sum256(b.Bytes())
	}
	return h
}

// ---------------------------------------------------------------------------
// Payload
// ---------------------------------------------------------------------------

type Payload struct {
	SchemaVersion string
	RunID         string
	Profile       string // eco | cruise | burn
	Timestamp     string // RFC3339 UTC

	BaseSHA    string
	HeadSHA    string
	DiffAlgo   string // versionisan, npr. "v1"
	DiffDigest Digest

	// adversarial faza -- dekontekstualizovana
	ReviewerModel          string
	ReviewerEffort         string
	ReviewerManifest       []Segment
	ReviewerContextDigest  Digest
	ReviewerTemplateDigest Digest
	FlagsDigest            Digest
	FlagsCount             uint32

	// tool-scope kanal -- dokaz da recenzent nije sam dosao do speca
	ReviewerToolScopeDigest Digest
	ReviewerToolCallsDigest Digest
	ReviewerToolCallsCount  uint32

	// adjudikacija -- kontekstualizovana
	AdjudicatorModel    string
	AdjudicatorManifest []Segment
	SpecDigest          Digest
	PlanDigest          Digest
	Verdict             string
}

// tagovi payload polja -- fiksni i nikad se ne reciklira
const (
	tSchema      uint16 = 0x1001
	tRunID       uint16 = 0x1002
	tProfile     uint16 = 0x1003
	tTimestamp   uint16 = 0x1004
	tBaseSHA     uint16 = 0x1010
	tHeadSHA     uint16 = 0x1011
	tDiffAlgo    uint16 = 0x1012
	tDiffDigest  uint16 = 0x1013
	tRevModel    uint16 = 0x1020
	tRevEffort   uint16 = 0x1021
	tRevManifest uint16 = 0x1022
	tRevCtxDig   uint16 = 0x1023
	tRevTmplDig  uint16 = 0x1024
	tFlagsDig    uint16 = 0x1025
	tFlagsCount  uint16 = 0x1026
	tRevScopeDig uint16 = 0x1027
	tRevCallsDig uint16 = 0x1028
	tRevCallsCnt uint16 = 0x1029
	tAdjModel    uint16 = 0x1030
	tAdjManifest uint16 = 0x1031
	tSpecDigest  uint16 = 0x1032
	tPlanDigest  uint16 = 0x1033
	tVerdict     uint16 = 0x1034
)

func encodeManifest(segs []Segment) []byte {
	var b bytes.Buffer
	putTLVU32(&b, 0x0001, uint32(len(segs)))
	for i, s := range segs {
		putTLVU32(&b, 0x0002, uint32(i))
		putTLV(&b, 0x0003, []byte{byte(s.Type)})
		putTLVDig(&b, 0x0004, s.Digest)
	}
	return b.Bytes()
}

// Canonical serijalizuje payload deterministicki. Redosled je fiksan u kodu,
// ne izveden iz mape -- nema iteracijske nedeterministicnosti.
func (p *Payload) Canonical() []byte {
	var b bytes.Buffer
	b.WriteString(domPayload)

	putTLVStr(&b, tSchema, p.SchemaVersion)
	putTLVStr(&b, tRunID, p.RunID)
	putTLVStr(&b, tProfile, p.Profile)
	putTLVStr(&b, tTimestamp, p.Timestamp)

	putTLVStr(&b, tBaseSHA, p.BaseSHA)
	putTLVStr(&b, tHeadSHA, p.HeadSHA)
	putTLVStr(&b, tDiffAlgo, p.DiffAlgo)
	putTLVDig(&b, tDiffDigest, p.DiffDigest)

	putTLVStr(&b, tRevModel, p.ReviewerModel)
	putTLVStr(&b, tRevEffort, p.ReviewerEffort)
	putTLV(&b, tRevManifest, encodeManifest(p.ReviewerManifest))
	putTLVDig(&b, tRevCtxDig, p.ReviewerContextDigest)
	putTLVDig(&b, tRevTmplDig, p.ReviewerTemplateDigest)
	putTLVDig(&b, tFlagsDig, p.FlagsDigest)
	putTLVU32(&b, tFlagsCount, p.FlagsCount)
	putTLVDig(&b, tRevScopeDig, p.ReviewerToolScopeDigest)
	putTLVDig(&b, tRevCallsDig, p.ReviewerToolCallsDigest)
	putTLVU32(&b, tRevCallsCnt, p.ReviewerToolCallsCount)

	putTLVStr(&b, tAdjModel, p.AdjudicatorModel)
	putTLV(&b, tAdjManifest, encodeManifest(p.AdjudicatorManifest))
	putTLVDig(&b, tSpecDigest, p.SpecDigest)
	putTLVDig(&b, tPlanDigest, p.PlanDigest)
	putTLVStr(&b, tVerdict, p.Verdict)

	return b.Bytes()
}

func Sign(key []byte, p *Payload) []byte {
	m := hmac.New(sha256.New, key)
	m.Write(p.Canonical())
	return m.Sum(nil)
}

// ---------------------------------------------------------------------------
// Validator
// ---------------------------------------------------------------------------

var (
	ErrMAC              = errors.New("korak 1: HMAC ne valja -- zapis je menjan")
	ErrDiffMismatch     = errors.New("korak 2: rekonstruisan diff se ne poklapa sa diff_digest")
	ErrChainMismatch    = errors.New("korak 3: manifest ne daje reviewer_context_digest")
	ErrContextLeak      = errors.New("korak 4: IZOLACIJA PROBIJENA -- zabranjen tip segmenta u recenzentovom kontekstu")
	ErrDiffSegment      = errors.New("korak 5: recenzentov DIFF segment nije tacno jedan ili ne odgovara diffu")
	ErrTemplateUntruted = errors.New("korak 6: challenger template nije na allowlist-i")
	ErrAdjContext       = errors.New("korak 7: adjudikator nema pinovan spec/plan/diff/flags")
)

// DiffBuilder rekonstruise kanonizovan diff iz repo-a. Determinizam je ovde
// obavezan: stabilan redosled fajlova, normalizovani line endings, bez
// timestamp-a u header-ima. Zato je algo versionisan.
type DiffBuilder func(baseSHA, headSHA, algo string) ([]byte, error)

type Validator struct {
	Key              []byte
	TrustedTemplates map[Digest]bool
	BuildDiff        DiffBuilder
}

func (v *Validator) Validate(p *Payload, mac []byte, ev *Evidence) error {
	// 1 -- integritet celog zapisa
	if !hmac.Equal(mac, Sign(v.Key, p)) {
		return ErrMAC
	}

	// 2 -- diff je bas ovaj, ceo, i nezavisno rekonstruisan iz gita
	canon, err := v.BuildDiff(p.BaseSHA, p.HeadSHA, p.DiffAlgo)
	if err != nil {
		return fmt.Errorf("korak 2: rekonstrukcija diffa: %w", err)
	}
	if DiffDigest(canon) != p.DiffDigest {
		return ErrDiffMismatch
	}

	// 3 -- manifest je kompletan i netaknut
	if HashChain(p.ReviewerManifest) != p.ReviewerContextDigest {
		return ErrChainMismatch
	}

	// 4 -- IZOLACIJA: nista osim role template + diff
	for _, s := range p.ReviewerManifest {
		if !reviewerAllowed[s.Type] {
			return fmt.Errorf("%w: %s", ErrContextLeak, s.Type)
		}
	}

	// 5 -- tacno jedan DIFF segment, i to bas taj diff
	//      (sprecava podmetanje speca zamaskiranog kao "diff")
	want := SegmentDigest(SegDiff, canon)
	n := 0
	for _, s := range p.ReviewerManifest {
		if s.Type == SegDiff {
			n++
			if s.Digest != want {
				return ErrDiffSegment
			}
		}
	}
	if n != 1 {
		return ErrDiffSegment
	}

	// 6 -- framing nije zamenjen template-om koji usmeno opisuje spec
	if !v.TrustedTemplates[p.ReviewerTemplateDigest] {
		return ErrTemplateUntruted
	}

	// 7 -- adjudikator SME kontekst, ali mu je ulaz pinovan
	seen := map[SegType]Digest{}
	for _, s := range p.AdjudicatorManifest {
		seen[s.Type] = s.Digest
	}
	for _, t := range []SegType{SegSpec, SegPlan, SegDiff, SegFlags} {
		if _, ok := seen[t]; !ok {
			return fmt.Errorf("%w: nedostaje %s", ErrAdjContext, t)
		}
	}
	if seen[SegSpec] != p.SpecDigest || seen[SegPlan] != p.PlanDigest {
		return fmt.Errorf("%w: spec/plan digest se ne poklapa", ErrAdjContext)
	}
	if seen[SegDiff] != want {
		return fmt.Errorf("%w: adjudikator je gledao drugi diff", ErrAdjContext)
	}

	// 8 -- TOOL KANAL: koraci 3-6 pokrivaju samo ono sto je harness stavio u
	//      prompt. Recenzent je agent: bez ovog koraka mogao je sam da procita
	//      spec, a potpis bi i dalje validirao. Evidence je obavezan -- bez
	//      loga poziva slepilo je tvrdnja, ne dokaz.
	if ev == nil {
		return ErrNoEvidence
	}
	if ev.ReviewerScope.Digest() != p.ReviewerToolScopeDigest {
		return ErrScopeMismatch
	}
	if ToolCallsChain(ev.ReviewerCalls) != p.ReviewerToolCallsDigest ||
		uint32(len(ev.ReviewerCalls)) != p.ReviewerToolCallsCount {
		return ErrCallsMismatch
	}
	for i, c := range ev.ReviewerCalls {
		if err := ev.ReviewerScope.Permits(c); err != nil {
			return fmt.Errorf("%w: poziv %d: %v", ErrOutOfScopeCall, i, err)
		}
	}

	return nil
}
