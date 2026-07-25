# APD: smernice za reimplementaciju

Verzija 3, jul 2026. Izmenjena posle projektne analize verzije 2.

## Šta se promenilo u odnosu na v2

Težište je bilo pogrešno postavljeno. Verzija 2 je tvrdila da potpis dokazuje slepilo recenzenta, a potpis dokazuje samo šta je harness stavio u prompt. Recenzent je agent sa alatima i može sam da pročita spec tokom run-a, dok hash-chain i dalje savršeno validira. Ta rupa je zatvorena tool-scope kanalom i novim korakom 8, a redosled implementacije je preokrenut.

Adjudikacija je mapirana na postojeći supervizijski sloj umesto da uvodi novu ulogu. Odeljak o Opus 5 je obeležen kao atestacija proizvođača, a preporuka za `eco` povučena do merenja u korpusu.

---

## 1. Šta se menja i zašto

Opus 5 je izašao 24. jula i pomera tri stvari koje utiču na APD: effort postaje native parametar, automatic fallback postaje native funkcija API-ja, i alati mogu da se menjaju usred razgovora bez invalidacije prompt keša.

Uz to, adversarial korak dobija jasniju definiciju. Njegova vrednost ne dolazi od toga koliko model zna, nego od toga što ne zna specifikaciju ni plan implementacije. Recenzent gleda diff hladno, bez namere koja stoji iza njega, i zato vidi ono što autor ne vidi.

---

## 2. Opus 5: atestacija proizvođača, nije izvršen dokaz

**Ceo ovaj odeljak prepričava objavu proizvođača. Nijedna brojka nije potvrđena u APD korpusu.** Preporuke u odeljku 3 koje stoje samo na ovim brojkama nose oznaku `[nepotvrđeno]`.

### Cena i pozicija

Opus 5 košta 5 USD po milionu ulaznih i 25 po milionu izlaznih tokena, isto kao Opus 4.8. Fable 5 je 10 i 50. Sonnet 5 je 3 i 15, uz uvodnu cenu 2 i 10 do kraja avgusta. API string je `claude-opus-5`.

### Effort i Fast mode

Effort je skala između inteligencije i štednje tokena, sa nivoima do high, xhigh i max. Fast mode je zasebna osa: oko 2,5 puta brže, po dvostrukoj osnovnoj ceni.

### Brojke iz objave

Na Frontier-Bench v0.1 Opus 5 nadmašuje sve modele i više nego duplira Opus 4.8, uz nižu cenu po zadatku. Na CursorBench 3.2 na max effort-u je u okviru 0,5 odsto Fable 5 vrhunskog skora, po upola nižoj ceni. Na high, xhigh i max daje veće performanse za dati trošak od svih ostalih modela. Na AutomationBench prolazi više zadataka od svih i na najnižem effort-u. Na OSWorld 2.0 nadmašuje najbolji rezultat Fable 5 uz nešto više od trećine cene.

### Ponašanje i alignment

Izveštaji iz early access-a opisuju istu osobinu: model proverava sopstveni rad i ne odustaje. U jednom slučaju je našao korenski uzrok bug-a koji je konkurentski model prijavio kao rešen popravivši samo simptom. U drugom je osporio predloženi dizajn i nije popustio kad je korisnik insistirao.

Na automatskom bihevioralnom auditu Opus 5 je najusklađeniji model do sada, sa najnižom stopom obmanjujućeg ponašanja i najmanjom podložnošću navođenju na zloupotrebu.

### Granice

Opus 5 ne pomera granicu u dvonamenskim sposobnostima. Iza Mythos 5 je i u biologiji i u ofanzivnoj sajber-bezbednosti. Blizu mu je u pronalaženju ranjivosti, znatno zaostaje u razvoju eksploita.

---

## 3. Profili i effort

Profil je trojka: model, effort, fast.

| Profil | Effort | Fast | Namena | Status |
|---|---|---|---|---|
| `eco` | low do medium | off | scaffolding, formatiranje, prosti transformi | `[nepotvrđeno]` |
| `cruise` | high do xhigh | off | podrazumevani radni koraci | `[nepotvrđeno]` |
| `burn` | max | opciono | teški koraci, root cause, finalni verdikt | `[nepotvrđeno]` |
| `endurance` | max (Fable 5) | off | run-ovi koji traju danima bez nadzora | `[nepotvrđeno]` |

### eco na low: povučeno do merenja

Verzija 2 je pravdala `eco` na `low` rezultatom sa AutomationBench-a. To je bila greška u vrsti, ne samo neproverena brojka. AutomationBench meri pass rate na drugoj distribuciji zadataka i ne kaže ništa o broju turn-ova ni o wall-clock-u.

Korpus ima direktan kontra-podatak. SEF Faza 4, eco i sonnet builderi na kompleksnom tasku: više turn-ova, 57 minuta, zaključak da eco štedi tokene a plaća wall-clock.

Pre nego što `eco` siđe na `low`, izmeri `apd report turns` na uporedivom tasku. Tabela nije dokaz.

### Verify slot

Prelazak na Opus 5 na max effort-u stoji na dva argumenta: cena je upola manja uz gotovo isti rezultat na CursorBench-u `[nepotvrđeno]`, i alignment profil je najbolji u familiji `[nepotvrđeno]`. Oba su atestacija. Fable ostaje u `endurance` profilu.

Pošto svi profili gađaju isti model, drift attribution postaje čistija: prompt cache ostaje stabilan, a jedina promenljiva je effort.

Fast mode drži kao zasebnu osu. On menja latenciju i cenu, ne dubinu razmišljanja. Spojen sa effort skalom, kvari drift attribution.

### Fallback

Automatic fallback rutira označene zahteve na drugi model umesto da ih blokira. U Claude.ai, Claude Code i Cowork podrazumevano padaju na Opus 4.8, a isto može da se uključi na API-ju. Time se pokriva postojeći APD anti-pattern: zahtev se ne preformuliše da bi se zaobišao klasifikator, nego se svesno prebacuje model.

Cyber klasifikatori na Opus 5 su blaži nego na Fable 5, uz očekivanih oko 85 odsto ređih intervencija `[nepotvrđeno]`. Dozvoljavaju traženje ranjivosti u source kodu, blokiraju binary-based skeniranje, penetration testing i generisanje eksploita. Biološki zahtevi blokirani na Fable 5 sada idu na Opus 5.

Adversarial korak ostaje izuzetak. On gura ivične formulacije i verovatnije okida klasifikator. Ako fallback tu radi tiho, recenzent oslabi usred posla a ti to ne vidiš. Izuzmi ga iz auto-fallback-a ili obeleži fallback u telemetriji.

Ovo je ista klasa kao postojeća rupa u kojoj serviran model nije logovan po run-u. Popravi obe istom kolonom.

Za ozbiljan security posao Cyber Verification Program daje verziju sa manje restrikcija, kao legitiman izlaz umesto zaobilaženja.

---

## 4. Tool scoping: nosivi mehanizam

**Ovo je jedina stvar koja stvarno proizvodi slepilo recenzenta.** Potpis iz odeljka 6 beleži šta je scoping sproveo, ali ga ne sprovodi.

### Zašto ovo nije dopuna nego temelj

Recenzent je agent sa alatima. Ako ima Read, pročitaće `.apd/pipeline/spec-card.md` tokom run-a jer je to najprirodnija stvar koju agent radi kad hoće da razume zadatak. Kontekst je i dalje bio čist, manifest i dalje glasi `[ROLE_TEMPLATE, DIFF]`, hash-chain i dalje validira, a tvrdnja o izolaciji je neistinita.

Jaz je realan i u postojećem kodu: `adversarial-reviewer-template.md` nigde ne pominje spec-card, dakle APD već namerava spec-slepog recenzenta, ali ga ne sprovodi.

### Scope po fazi

Alati sada mogu da se menjaju unutar razgovora bez invalidacije prompt keša, pa svaka faza može da ima svoj grant bez rušenja keša pri prelasku.

| Faza | Grant |
|---|---|
| producer | pun scope |
| adversarial reviewer | samo čitanje diffa, deny na spec i plan putanje |
| supervizor (adjudikacija) | čitanje speca, plana, diffa i flagova |

Deny lista je redundantna uz allow listu i to je namerno. Dva nezavisna uslova moraju oba da padnu da bi spec procurio.

Hooks ostaju mesto gde se scope sprovodi, jer već presreću sve pozive alata. Mid-conversation promena je mehanizam koji to čini jeftinim.

### Scoping bez zapisa ne dokazuje ništa

Tool scoping sprovodi slepilo u runtime-u i ne ostavlja artefakt. Potpis beleži ulaz i ništa ne sprovodi. Nijedan sam po sebi ne daje post-hoc dokaz.

Zato hooks moraju da emituju log poziva koji ulazi u potpis. Bez toga ponavljaš isti jaz između namere i sprovođenja koji je i doveo do rupe u v2.

---

## 5. Adversarial: korak, ne profil

Adversarial postoji u svakom profilu kao jedan korak. Recenzent dobija diff i ništa više, i u kontekstu i u alatima.

### Podela rada

Recenzent hvata probleme unutar samog diffa: internu nekonzistentnost, logičku rupu vidljivu u kodu, nebezbedan obrazac, mrtvu granu. Spec-conformance ne može da proveri jer nema spec. To nije mana nego podela posla.

Supervizor ima spec i plan, pa proverava da li diff radi ono što je traženo.

### Adjudikacija se mapira na postojeći supervizijski sloj

Adjudikator iz v2 je po ulozi već isporučeni supervizor. Isti ulazi, isti posao. Nova uloga se ne uvodi, jer bi dala šest hopova umesto pet.

Ali preklapanje je u ulozi, ne u vremenu. Supervizor je post-pipeline i zove se jednom, sa finality check-om i churn cap-om građenim za jedan poziv. Adversarial je po koraku i okida N puta. Naivno spajanje lomi jedno od dva: ili flagovi sa trećeg koraka čekaju kraj run-a i gubiš petlju povratne informacije tamo gde je najjeftinija, ili supervizor postaje N poziva i gubiš finality check.

Rešenje: jedna definicija uloge, dva mesta poziva.

- Isti `supervisor-template.md` i isti charter, dopunjen petim pitanjem o razrešenju flagova.
- Inline poziv razrešava flagove po koraku.
- Finalni poziv zadržava postojeću ulogu, finality check i churn cap.
- Telemetrija ostaje `SUPERVISION:T:A:D` sa dodatnim brojačem razrešenih flagova, bez novog namespace-a.
- Profile binding se nasleđuje, ne dupliira.

### Izbor modela za recenzenta

Sonnet 5 je default. Jeftin je, a spec-slepost je upravo ono što tražiš. Nije oslabljen recenzent nego namerno neinformisan.

Fable 5 ulazi samo kad je diff toliko gust da plitak pogled ne registruje defekt iako je vidljiv. Uzak slučaj, ne pravilo. Fable ima poznat problem sa potrošnjom i ume da pojede budžet pipeline-a kad radi na svakom koraku.

### Recenzent daje sumnje, ne presude

Spec-slep recenzent prijaviće stvari koje izgledaju pogrešno a namerne su po specu koji ne vidi. Viši false-positive rate je cena objektivnosti, ne bug. To formalizuje ono što APD već radi neformalno kroz accept i dismiss trijažu.

Recenzent je slep, sudija nije. Nikad obrnuto.

```yaml
adversarial_step:
  reviewer:
    model: claude-sonnet-5
    context: diff_only
    tool_scope:
      allow_tools: [read_diff]
      allow_paths: [".apd/run/diff/"]
      deny_paths: [".apd/pipeline/spec-card.md", ".apd/pipeline/plan"]
    role: challenger
    output: flags
    escalate_reviewer:
      model: claude-fable-5
      when: diff_complexity_high

  adjudication:
    role: supervisor          # postojeci sloj, inline poziv
    template: supervisor-template.md
    context: full
    resolves: [real_defect, spec_explained_false_positive]
    telemetry: SUPERVISION:T:A:D
```

### Granica nezavisnosti

Sonnet 5, Opus 5 i Fable 5 dele isti trening lineage, pa dele i deo sistematskih slepih mrlja. Cross-tier recenzent donosi raznolikost kapaciteta, ne raznolikost pristrasnosti. Prava ortogonalnost tražila bi drugog vendora, što iz jedne CLI sesije nije izvodljivo.

Upiši `within-family independence` kao kolonu u telemetriji. Jedna kolona, trajna zaštita od precenjivanja nezavisnosti.

---

## 6. Potpis: tamper-evidence nad oba kanala

`.done` tvrdi da je diff pregledan slepo za spec i da su flagovi presuđeni protiv speca. Da bi ta tvrdnja bila tačna, potpis mora da pokrije oba kanala kojima spec može da stigne: prompt i alate.

Ne možeš da dokažeš da model nešto nije video, pa se dokaz seli na ulaz. Heširaš šta je predato i šta je dohvaćeno.

### Kontekst kao niz segmenata

Kontekst je uređen niz segmenata, svaki `(tip, sadržaj)` sveden na digest. `reviewer_context_digest` je hash-chain preko svih segmenata redom. Recenzentu su dozvoljeni samo `ROLE_TEMPLATE` i `DIFF`.

Lanac ide preko svih segmenata, pa skriveni segment slomi potpis.

### Log poziva kao drugi lanac

`reviewer_tool_calls_digest` je hash-chain preko svih poziva alata koje su hooks presreli, po redu. `reviewer_tool_scope_digest` fiksira grant pod kojim su izvedeni. Prećutan poziv menja lanac isto kao prećutan segment.

### Polja u potpisanom payload-u

```
schema_version, run_id, profile, timestamp

base_sha, head_sha, diff_algo, diff_digest

reviewer_model, reviewer_effort
reviewer_context_manifest       # [{ROLE_TEMPLATE, digest}, {DIFF, digest}]
reviewer_context_digest         # hashchain preko manifesta
reviewer_template_digest
reviewer_tool_scope_digest      # grant
reviewer_tool_calls_digest      # hashchain preko loga poziva
reviewer_tool_calls_count
flags_digest, flags_count

adjudicator_model               # = supervizor
adjudicator_context_manifest    # spec, plan, diff, flags
spec_digest, plan_digest
verdict

mac                             # HMAC-SHA256 preko svega gore
```

### Redosled provera u validatoru

1. HMAC se poklapa. Ništa nije menjano.
2. Diff rekonstruisan iz `base_sha` i `head_sha` daje `diff_digest`.
3. Hash-chain preko manifesta daje `reviewer_context_digest`.
4. Svaki tip segmenta je na allowlist-i.
5. Tačno jedan `DIFF` segment, i njegov digest odgovara rekonstruisanom diffu.
6. `reviewer_template_digest` je na allowlist-i poverljivih challenger template-a.
7. Supervizor ima spec, plan, diff i flags, i gledao je isti diff.
8. **Evidence je prisutan; scope i log poziva odgovaraju digestima; nijedan poziv ne izlazi iz grant-a.**

Koraci 3 do 6 pokrivaju prompt kanal. Korak 8 pokriva tool kanal. Bez koraka 8 recenzent može sam da donese spec, a validator to ne vidi.

Bez `Evidence` validacija pada. To je namerno: bez loga poziva slepilo je tvrdnja, ne dokaz.

### Napadi i koraci koji ih hvataju

| Napad | Kanal | Hvata ga |
|---|---|---|
| Spec ubačen i pošteno prijavljen u manifestu | prompt | korak 4 |
| Spec ubačen ali prećutan u manifestu | prompt | korak 3 |
| Spec zamaskiran kao `DIFF` segment | prompt | korak 5 |
| Template koji usmeno prepričava spec | prompt | korak 6 |
| **Recenzent sam pročitao spec tokom run-a** | **alati** | **korak 8** |
| **Poziv van scope-a prećutan u logu** | **alati** | **korak 8** |
| **Scope naknadno proširen da poziv izgleda dozvoljeno** | **alati** | **korak 8** |
| Izmena verdikta posle potpisivanja | oba | korak 1 |
| Adjudikacija nad drugim diffom | prompt | korak 7 |

Peti red je onaj koji je nedostajao u v2 i koji je obarao centralnu tvrdnju. Prompt je bio čist, koraci 3 do 6 prolaze, a spec je ipak stigao.

### Kanal koji se ne može zatvoriti

Spec može legitimno da uđe kroz sam diff: kroz commit poruke, docstring-ove, ili izmenu samog spec fajla. Ako diff dira spec-card, recenzent ga vidi s pravom i nijedan korak to ne sprečava.

Taj slučaj se ne zatvara, nego prijavljuje. Obeleži run u telemetriji kao smanjenu nezavisnost kad diff dira putanje speca.

---

## 7. Serijalizacija

TLV umesto canonical JSON: `(tag uint16, len uint32, value)`. Length-prefix svuda znači da granice polja nisu dvosmislene, pa cela klasa canonical-JSON napada otpada, od whitespace-a i redosleda ključeva do duplikata i unicode escape varijanti.

Redosled polja fiksiraj u kodu, ne izvodi ga iz mape. Go map iteracija nije deterministična.

Domain separation na svakom hash-u, sa zasebnim prefiksom za segment, korak lanca konteksta, scope, korak lanca poziva, diff i payload.

Tip mora da ulazi u segment digest, tako da `digest(SPEC, x)` nikad nije jednak `digest(DIFF, x)`.

### Kanonizacija diffa

`BuildDiff` mora da bude determinističan bajt za bajt: stabilan redosled fajlova, normalizovani line endings, bez timestamp-a u header-ima. Ako nije, korak 2 puca i na poštenim run-ovima.

Zato `diff_algo` versioniši, a diff izvodi iz `base_sha` i `head_sha` preko gita umesto da čuvaš bajtove.

---

## 8. Harness: prompt kao izvedena vrednost

Prompt nije zaseban buffer koji se piše paralelno sa manifestom. Prompt je čista funkcija segmenata: `prompt = RenderPrompt(segments)`. Nema exported writer-a, `Add()` je jedini ulaz u kontekst.

Zato ne postoji način da bajt uđe u prompt a ne završi u manifestu. Drift između to dvoje nije stvar discipline nego je strukturno nemoguć.

Isti princip važi i za tool kanal: log poziva ne piše se ručno pored hooks-a, nego ga hooks emituju, jer već presreću sve pozive. Zapis je potpun po konstrukciji, ne po disciplini.

Builder odbija zabranjen tip na `Add()`, dakle pre poziva modela. Validator ostaje nezavisan svedok, a ne jedina odbrana.

Sitnice koje zatvaraju rupe koje se lako previde:

- `Add()` pravi defanzivnu kopiju sadržaja, inače caller zadrži referencu i promeni sadržaj posle računanja digesta.
- `Seal()` zaključava builder, pa nema dopisivanja posle pečaćenja.
- Recenzent bez `DIFF` segmenta i supervizor bez speca ne mogu da se zapečate.
- Digeste u payload vadi iz manifesta i iz loga poziva, ne prepisuj ih ručno.

### Granice segmenata

Segmente u promptu razdvoj nasumičnim nonce-om po run-u, u obliku `<<<APD:{nonce}:DIFF>>>`, da sadržaj ne može da falsifikuje granicu.

To je mitigacija prompt injection-a, ne deo kriptografske garancije. Digest ostaje tačan i kad model pogrešno pročita granicu.

---

## 9. Šta ovaj dizajn ne dokazuje

HMAC ključ je koren poverenja. Ko drži ključ, može da falsifikuje bilo šta.

Trust boundary je harness koji gradi prompt, sprovodi scope i računa digeste u runtime-u. Hooks su deo harness-a, pa kompromitovan harness ruši i prompt kanal i tool kanal.

Poštena formulacija: izolacija je verifikabilna protiv poverljivog harness-a i tamper-evidentna post-hoc. Nije nemoguće slagati.

Dodatno, korak 8 dokazuje da recenzent nije dohvatio spec kroz alat. Ne dokazuje da spec nije stigao kroz sam diff, ni da model nije nešto zaključio iz opšteg znanja o projektu.

Odeljak 2 je atestacija proizvođača i po istom kriterijumu ne prolazi kao dokaz.

---

## 10. Redosled implementacije

1. **Tool scoping po fazi** kroz mid-conversation promene, sa hooks kao mestom sprovođenja. Najveći odnos vrednosti i cene, uklapa se u postojeće hookove, i jedini stvarno proizvodi slepilo.
2. **Emisija loga poziva iz hooks-a.** Ide odmah uz prvi korak, jer scoping bez zapisa ostavlja isti jaz između namere i dokaza.
3. **Obeležavanje fallback-a** u telemetriji, zajedno sa logovanjem serviranog modela po run-u. Jeftino, zatvara tihu degradaciju.
4. **`within-family independence`** kao kolona u telemetriji.
5. **Harness builder.** Strukturno, vredno, bez kriptografije.
6. **Potpis, koraci 1 do 8**, tek kad prethodno stoji.
7. **Uklanjanje starog puta** za konstrukciju prompta, poslednje. Dok builder ne radi, validator hvata greške koje bi inače prošle tiho.
8. **Merenje effort profila** preko `apd report turns` pre nego što se `eco` spusti na `low`.

---

## Reference

Referentna Go implementacija: `done.go` (TLV, hash-chain konteksta, validator 1 do 8), `toolscope.go` (scope, lanac poziva, korak 8) i `harness.go` (builder, pečaćenje run-a). 22 testa, uključujući devet napada iz tabele u odeljku 6.

Objava proizvođača: https://www.anthropic.com/news/claude-opus-5
