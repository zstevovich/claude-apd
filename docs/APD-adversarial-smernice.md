# APD: smernice za reimplementaciju

Objedinjeno, verzija 2, jul 2026. Pokriva promene koje donosi Opus 5, profile i effort, tool scoping po fazi, adversarial sloj i verifikabilan `.done` potpis.

---

## 1. Šta se menja i zašto

Opus 5 je izašao 24. jula i pomera tri stvari koje direktno utiču na APD.

Effort postaje native parametar modela, pa profil prestaje da bude samo izbor modela. Automatic fallback postaje native funkcija API-ja i pokriva deo logike koju APD sada nosi ručno. Alati mogu da se menjaju usred razgovora bez invalidacije prompt keša, što otvara tool scoping po fazi pipeline-a.

Uz to, adversarial korak dobija jasniju definiciju. Njegova vrednost ne dolazi od toga koliko model zna, nego od toga što ne zna specifikaciju ni plan implementacije. Recenzent gleda diff hladno, bez namere koja stoji iza njega, i zato vidi ono što autor ne vidi.

---

## 2. Opus 5: činjenice koje ulaze u odluke

### Cena i pozicija

Opus 5 košta 5 USD po milionu ulaznih i 25 USD po milionu izlaznih tokena, isto kao Opus 4.8. Fable 5 je dvostruko skuplji, 10 i 50 USD. Sonnet 5 je 3 i 15 USD, uz uvodnu cenu 2 i 10 do kraja avgusta.

Opus 5 je novi podrazumevani model na Claude Max i najjači dostupan na Claude Pro. API string je `claude-opus-5`.

### Effort i Fast mode

Effort je skala kojom biraš između inteligencije i štednje tokena. Nivoi idu do high, xhigh i max.

Fast mode je zasebna osa: oko 2,5 puta brže od podrazumevane brzine, po dvostrukoj osnovnoj ceni. Dostupan je na Claude Platform i kroz usage credits u Claude Code.

### Rezultati koji menjaju izbor modela

Na Frontier-Bench v0.1 Opus 5 nadmašuje sve modele i više nego duplira rezultat Opus 4.8, uz nižu cenu po zadatku.

Na CursorBench 3.2, na max effort-u, Opus 5 je u okviru 0,5 odsto Fable 5 vrhunskog skora, po upola nižoj ceni po zadatku. Na high, xhigh i max effort-u daje veće performanse za dati trošak od svih ostalih modela.

Na AutomationBench Opus 5 prolazi više zadataka od bilo kog drugog modela čak i na najnižem effort-u.

Na OSWorld 2.0 nadmašuje najbolji rezultat Fable 5 uz nešto više od trećine cene.

### Ponašanje

Više izveštaja iz early access-a opisuje istu osobinu: model proverava sopstveni rad i ne odustaje dok ne uspe. U jednom slučaju je našao korenski uzrok bug-a i popravio edge case koji je zajednici promakao, dok je konkurentski model popravio samo simptom pa prijavio da je gotovo. U drugom je osporio predloženi dizajn i nije popustio kad je korisnik insistirao, nego je suzio primedbu na jedno pitanje i ponudio kompromis.

### Alignment

Na automatskom bihevioralnom auditu Opus 5 je najusklađeniji model do sada. Ima najnižu stopu obmanjujućeg ponašanja, najmanje je podložan navođenju na zloupotrebu i bolje poštuje Claude's Constitution nego Opus 4.8, Sonnet 5 i Fable 5.

Ovo je drugi argument za Opus 5 u verify slotu, pored cene. Sloj koji donosi finalni verdikt treba da bude onaj koji najređe glumi da je zadatak rešen.

### Granice

Opus 5 ne pomera granicu u rizičnim, dvonamenskim sposobnostima. Iza Mythos 5 je i u biologiji i u ofanzivnoj sajber-bezbednosti. Blizu mu je u pronalaženju ranjivosti, ali znatno zaostaje u razvoju eksploita.

Za APD to znači da Fable i Mythos ostaju relevantni samo za uzak skup poslova, ne kao podrazumevani izbor.

---

## 3. Profili i effort

Profil više nije „koji model", nego trojka: model, effort, fast.

| Profil | Effort | Fast | Namena |
|---|---|---|---|
| `eco` | low do medium | off | scaffolding, formatiranje, prosti transformi |
| `cruise` | high do xhigh | off | podrazumevani radni koraci |
| `burn` | max | opciono | teški koraci, root cause, finalni verdikt |
| `endurance` | max (Fable 5) | off | run-ovi koji traju danima bez nadzora |

Cost-efficiency sweet spot je gore, ne u sredini, pa `cruise` sedi na high i xhigh. A `eco` na `low` nije rizičan kao ranije, jer i najniži effort prolazi više zadataka od bilo kog drugog modela.

Fast mode drži kao zasebnu osu, ne kao effort nivo. On menja latenciju i cenu, ne dubinu razmišljanja. Ako ga spojiš sa effort skalom, drift attribution počinje da meša „sporije jer teže misli" sa „sporije jer je jeftiniji mod".

Verify slot prelazi na Opus 5 na max effort-u, iz dva razloga: cena je upola manja uz gotovo isti rezultat, a alignment profil je najbolji u familiji. Fable ostaje samo u `endurance` profilu, jer Anthropic i dalje preporučuje Fable 5 za projekte koje model vodi autonomno danima.

Pošto sada svi profili gađaju isti model, drift attribution postaje čistija. Prompt cache ostaje stabilan, a jedina promenljiva je effort.

### Fallback

Automatic fallback rutira zahteve koje označi bezbednosni klasifikator na drugi model umesto da ih blokira. U Claude.ai, Claude Code i Cowork označeni zahtevi podrazumevano padaju na Opus 4.8, a isto može da se uključi i na API-ju.

Time se pokriva postojeći APD anti-pattern: zahtev se ne preformuliše da bi se zaobišao klasifikator, nego se svesno prebacuje model.

Rizik je manji nego što je bio. Cyber klasifikatori na Opus 5 su blaži nego na Fable 5 i očekuje se da interveniše oko 85 odsto ređe. Dozvoljavaju traženje ranjivosti u source kodu, a blokiraju binary-based skeniranje, penetration testing i generisanje eksploita. Biološki zahtevi koji se blokiraju na Fable 5 sada idu na Opus 5, ne na Opus 4.8.

Jedan izuzetak ostaje. Adversarial korak po prirodi gura ivične formulacije i verovatnije okida klasifikator od ostalih koraka. Ako fallback tu radi tiho, recenzent oslabi usred posla a ti to ne vidiš. Ili izuzmi adversarial iz auto-fallback-a, ili obeleži fallback u telemetriji tako da drift detection zna da je verdikt donet oslabljenim modelom.

Ako neki APD korisnik radi ozbiljan security posao, Cyber Verification Program daje pristup verziji Opus 5 sa manje restrikcija. To je izlaz za slučaj kad safeguards smetaju legitimnom radu, umesto zaobilaženja.

---

## 4. Tool scoping po fazi

Alati sada mogu da se menjaju unutar razgovora bez invalidacije prompt keša.

Za APD to znači da svaka faza pipeline-a može da ima svoj tool scope, a da se keš ne ruši pri prelasku. Ranije si birao između jednog širokog scope-a za ceo run i rušenja keša pri svakoj promeni.

Praktične posledice:

Producer dobija pun scope. Recenzent ne dobija ništa osim čitanja diffa, što je i tehnička potpora izolaciji iz odeljka 6: ne oslanjaš se samo na to šta mu je u kontekstu, nego mu i uskraćuješ alat kojim bi sam pročitao spec iz repozitorijuma. Adjudikator dobija čitanje speca i plana.

Ovo se dobro slaže sa postojećim dizajnom u kom hooks presreću sve pozive alata. Hooks ostaju mesto gde se scope sprovodi, a mid-conversation promena je mehanizam koji to čini jeftinim.

Napomena o granici: uskraćivanje alata jača izolaciju, ali je ne dokazuje. Dokaz i dalje daje potpis iz odeljka 6.

---

## 5. Adversarial: korak, ne profil

Adversarial postoji u svakom profilu kao jedan korak pipeline-a. Recenzent dobija diff i ništa više.

### Podela rada sa verify slojem

Dekontekstualizovan recenzent i kontekstualizovan supervisor rade dva različita posla i ne zamenjuju se.

Recenzent hvata probleme unutar samog diffa: internu nekonzistentnost, logičku rupu vidljivu u kodu, nebezbedan obrazac, mrtvu granu. Spec-conformance ne može da proveri, jer nema spec. To nije mana nego podela posla.

Verify sloj ima spec i plan, pa proverava da li diff radi ono što je traženo.

Drži ih razdvojene i u kodu i u telemetriji. Model se za njih bira po različitoj logici.

### Izbor modela za recenzenta

Sonnet 5 je default. Jeftin je, a njegova spec-slepost je upravo ono što tražiš. Nije to oslabljen recenzent, nego namerno neinformisan.

Fable 5 ulazi samo kad je diff toliko gust da plitak pogled ne registruje defekt iako je vidljiv. To je uzak slučaj, ne pravilo. Fable ima i poznat problem sa potrošnjom, jer troši veliki broj tokena i probija budžete. Recenzent koji radi na svakom koraku ume tako da pojede ceo budžet pipeline-a.

### Recenzent daje sumnje, ne presude

Spec-slep recenzent će prijaviti stvari koje izgledaju pogrešno a namerne su po specu koji ne vidi. Viši false-positive rate je cena objektivnosti, ne bug.

Zato izlaz recenzenta ide na kontekstualizovanu adjudikaciju, koja svaki flag razrešava kao stvaran defekt ili kao lažni alarm objašnjen specom. Recenzent je slep, sudija nije. Nikad obrnuto.

```yaml
adversarial_step:
  reviewer:
    model: claude-sonnet-5
    context: diff_only
    tool_scope: read_diff_only
    role: challenger
    output: flags
    escalate_reviewer:
      model: claude-fable-5
      when: diff_complexity_high

  adjudication:
    model: <profile_verify_model>
    context: full
    tool_scope: read_spec_plan_diff
    resolves: [real_defect, spec_explained_false_positive]
```

### Granica nezavisnosti

Sonnet 5, Opus 5 i Fable 5 dele isti trening lineage, pa dele i deo sistematskih slepih mrlja. Cross-tier recenzent donosi raznolikost kapaciteta, ne dubinsku raznolikost pristrasnosti. Prava ortogonalnost tražila bi drugog vendora, što iz jedne CLI sesije nije izvodljivo.

Upiši to u telemetriju kao `within-family independence`, da kasnije ne precenjuješ koliko je adversarial korak zaista nezavisan.

---

## 6. Potpis: izolacija kao proverljiva tvrdnja

`.done` više ne tvrdi „adversar je rekao OK". Tvrdi da je diff nezavisno pregledan slepo za spec, i da su flagovi presuđeni protiv speca. To su dve razdvojene faze, obe pinovane u istom potpisu.

Ne možeš da dokažeš da model nešto nije video. Zato se dokaz seli na ulaz: heširaš tačno ono što je recenzentu predato i vežeš to u potpis.

### Kontekst kao niz segmenata

Kontekst je uređen niz segmenata, svaki `(tip, sadržaj)` sveden na digest. Ukupni `reviewer_context_digest` je hash-chain preko svih segmenata redom.

Izolacija se tako svodi na tvrdnju o skupu tipova. Recenzentu su dozvoljeni samo `ROLE_TEMPLATE` i `DIFF`. Nijedan `SPEC`, `PLAN` ni `PRODUCER_REASONING` ne sme da postoji.

Lanac ide preko svih segmenata, pa skriveni segment slomi potpis. Sakriven spec znači neuspelu validaciju.

### Polja u potpisanom payload-u

```
schema_version, run_id, profile, timestamp

base_sha, head_sha, diff_algo, diff_digest

reviewer_model, reviewer_effort
reviewer_context_manifest      # [{ROLE_TEMPLATE, digest}, {DIFF, digest}]
reviewer_context_digest        # hashchain preko manifesta
reviewer_template_digest
flags_digest, flags_count

adjudicator_model
adjudicator_context_manifest   # spec, plan, diff, flags
spec_digest, plan_digest
verdict

mac                            # HMAC-SHA256 preko svega gore
```

### Redosled provera u validatoru

1. HMAC se poklapa. Ništa nije menjano.
2. Diff rekonstruisan iz `base_sha` i `head_sha` daje `diff_digest`.
3. Hash-chain preko manifesta daje `reviewer_context_digest`.
4. Svaki tip segmenta je na allowlist-i. **Ovo je izolacija.**
5. Tačno jedan `DIFF` segment, i njegov digest odgovara rekonstruisanom diffu.
6. `reviewer_template_digest` je na allowlist-i poverljivih challenger template-a.
7. Adjudikator ima spec, plan, diff i flags, i gledao je isti diff.

Korak 4 je srce. Svi ostali postoje da bi korak 4 imao smisla. Bez koraka 3 mogao bi da lažeš manifest. Bez koraka 5 mogao bi da podmetneš spec zamaskiran kao diff. Bez koraka 6 mogao bi da recenzentu daš template koji mu usmeno prepriča spec.

### Napadi i koraci koji ih hvataju

| Napad | Hvata ga |
|---|---|
| Spec ubačen i pošteno prijavljen u manifestu | korak 4 |
| Spec ubačen ali prećutan u manifestu | korak 3 |
| Spec zamaskiran kao `DIFF` segment | korak 5 |
| Template koji usmeno prepričava spec | korak 6 |
| Izmena verdikta posle potpisivanja | korak 1 |
| Adjudikacija nad drugim diffom | korak 7 |

Četvrti red je onaj koji se najlakše previdi. Možeš savršeno da poštuješ pravilo o dozvoljenim tipovima, a u sam template ubaciš rečenicu o tome šta spec traži, i objektivnost je gotova bez ijednog zabranjenog segmenta.

---

## 7. Serijalizacija

TLV umesto canonical JSON: `(tag uint16, len uint32, value)`. Length-prefix svuda znači da granice polja nisu dvosmislene, pa cela klasa canonical-JSON napada otpada, od whitespace-a i redosleda ključeva do duplikata i unicode escape varijanti.

Redosled polja fiksiraj u kodu, ne izvodi ga iz mape. Go map iteracija nije deterministična.

Domain separation na svakom hash-u, sa zasebnim prefiksom za segment, korak lanca, diff i payload. Bez toga digest iz jednog konteksta može da se reinterpretira kao digest iz drugog.

Tip mora da ulazi u segment digest, tako da `digest(SPEC, x)` nikad nije jednak `digest(DIFF, x)`. Inače se `SPEC` preimenuje u `DIFF` uz isti digest.

### Kanonizacija diffa

`BuildDiff` mora da bude determinističan bajt za bajt: stabilan redosled fajlova, normalizovani line endings, bez timestamp-a u header-ima. Ako nije, korak 2 puca i na poštenim run-ovima.

Zato `diff_algo` versioniši, a diff izvodi iz `base_sha` i `head_sha` preko gita umesto da čuvaš bajtove. Tako se `diff_digest` vezuje za integritet repozitorijuma, a ne za nešto što harness može da regeneriše drugačije.

---

## 8. Harness: prompt kao izvedena vrednost

Ovo je najvažniji deo implementacije.

Prompt nije zaseban buffer koji se piše paralelno sa manifestom. Prompt je čista funkcija segmenata: `prompt = RenderPrompt(segments)`. Nema exported writer-a, `Add()` je jedini ulaz u kontekst.

Zato ne postoji način da bajt uđe u prompt a ne završi u manifestu. Drift između to dvoje nije stvar discipline nego je strukturno nemoguć. Umesto pravila „harness mora pošteno da vodi dva sinhrona zapisa", dobijaš jedan zapis.

Builder odbija zabranjen tip na `Add()`, dakle pre poziva modela. Validator ostaje kao nezavisan svedok, a ne kao jedina odbrana. Razlika je bitna: validator hvata curenje tek pošto je recenzent već video spec, builder ga ne pusti do modela.

Sitnice koje zatvaraju rupe koje se lako previde:

- `Add()` pravi defanzivnu kopiju sadržaja, inače caller zadrži referencu i promeni sadržaj posle računanja digesta.
- `Seal()` zaključava builder, pa nema dopisivanja posle pečaćenja.
- Recenzent bez `DIFF` segmenta i adjudikator bez speca ne mogu da se zapečate. Nepotpuna faza ne proizvodi validan potpis.
- Digeste u payload vadi iz manifesta, ne prepisuj ih ručno. To je jedno mesto manje gde payload može da laže o onome što je model dobio.

### Granice segmenata

Segmente u promptu razdvoj nasumičnim nonce-om po run-u, u obliku `<<<APD:{nonce}:DIFF>>>`. Tako sadržaj diffa ne može da falsifikuje granicu i navede model da jedan segment pročita kao dva.

To je mitigacija prompt injection-a, ne deo kriptografske garancije. Digest ostaje tačan i kad model pogrešno pročita granicu. Napiši to eksplicitno u kodu, da se kasnije ne pomeša sa integritetom.

---

## 9. Šta ovaj dizajn ne dokazuje

HMAC ključ je koren poverenja. Ko drži ključ, može da falsifikuje bilo šta.

Trust boundary je harness koji gradi prompt i računa digeste u runtime-u. On drži i ključ, pa ako je kompromitovan, cela priča pada.

Poštena formulacija garancije glasi: izolacija je verifikabilna protiv poverljivog harness-a i tamper-evidentna post-hoc. Nije „nemoguće slagati". I dalje je znatno jače od jednog OK bita, ali razlika je bitna kad kasnije budeš odlučivao koliko da veruješ potpisu.

Isto važi i za tool scoping iz odeljka 4. Uskraćen alat smanjuje priliku, ali dokaz daje potpis.

---

## 10. Redosled implementacije

1. Effort dial u profilima i telemetrija koja atribuira drift na effort, ne samo na model.
2. Native automatic fallback, uz izuzetak ili eksplicitno obeležavanje za adversarial korak.
3. Tool scoping po fazi kroz mid-conversation promene, sa hooks kao mestom sprovođenja.
4. Razdvajanje adversarial koraka od verify sloja, sa flag i adjudikacija tokom.
5. TLV serijalizacija i hash-chain, uz determinističku kanonizaciju diffa.
6. Validator, koraci 1 do 7.
7. Harness builder, pa tek onda uklanjanje starog puta za konstrukciju prompta.

Sedmi korak ide poslednji namerno. Dok builder ne radi, validator hvata greške koje bi inače prošle tiho.

---

## Reference

Referentna Go implementacija: `done.go` (TLV, hash-chain, validator) i `harness.go` (builder, pečaćenje run-a), sa 17 testova koji pokrivaju napade iz tabele u odeljku 6.

Zvanična objava: https://www.anthropic.com/news/claude-opus-5
