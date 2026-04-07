# Principi

## Jezik
- Dokumentacija i komunikacija: srpski, latinica
- Stručni termini ostaju na engleskom: endpoint, middleware, handler, cache
- Ton: profesionalan i konkretan, ne sme zvučati AI-generisano

## Kod
- Minimalni komentari — samo gde logika nije očigledna
- Aplikacija podržava višejezičnost (i18n) od početka

## Git
- Nema AI potpisa u commitima — nikakav Co-Authored-By
- Grane: develop → staging → main, feature/* po potrebi
- .claude/ direktorijum ne sme na git
- Commit poruke: kratke, na engleskom, imperative mood

## Docker (lokalni razvoj)
- Samo infrastruktura (baza, cache, monitoring)
- Aplikacije iz debug moda (IDE)
