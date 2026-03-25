# Principi

## Jezik
- [Jezik dokumentacije i komunikacije]
- Stručni termini ostaju na engleskom: endpoint, middleware, handler, cache, repository
- Ton: profesionalan i konkretan

## Kod
- Minimalni komentari — samo gde logika nije očigledna
- [Error handling pattern — Result, exceptions, ili hybrid] (vidi ADR-NNNN)
- [Arhitekturni pattern — Vertical Slice, Clean Architecture, itd.] (vidi ADR-NNNN)
- Arhitekturne odluke se dokumentuju kao ADR u `docs/adr/`

## Git
- Nema AI potpisa u commitima — nikakav Co-Authored-By
- Grane: develop → staging → main, feature/* po potrebi
- .claude/ direktorijum je deo repozitorijuma (deljeni workflow)
