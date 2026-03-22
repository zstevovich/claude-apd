# Konvencije

Projektno-specifične konvencije za imenovanje, strukturu i obrasce.
**PRILAGODITI** za svoj projekat — otkomentariši i popuni relevantne sekcije.

## Imenovanje

### Fajlovi i direktorijumi
- [Pattern: npr. kebab-case za fajlove, PascalCase za komponente]
- [Primer: `user-service.ts`, `UserProfile.tsx`]

### Kod
- [Varijable/funkcije: npr. camelCase]
- [Klase/tipovi: npr. PascalCase]
- [Konstante: npr. UPPER_SNAKE_CASE]
- [Booleans: npr. prefiks is/has/can — `isActive`, `hasPermission`]

## Struktura fajlova

### Backend
- [Gde idu novi endpointi: npr. `src/features/{feature}/`]
- [Gde idu modeli/DTO-ovi: npr. `src/features/{feature}/models/`]
- [Gde idu testovi: npr. `tests/{feature}/`]

### Frontend
- [Gde idu komponente: npr. `apps/web/src/components/`]
- [Gde idu page-ovi: npr. `apps/web/src/pages/`]
- [Gde idu hook-ovi: npr. `apps/web/src/hooks/`]

## Error Handling

- [Pattern: npr. Result<T>, exceptions, ili hybrid]
- [Gde se hvataju greške: npr. na granici sloja — handler/controller]
- [Logging: npr. strukturirani log sa correlation ID]

## Testovi

- [Naming: npr. `should_return_404_when_user_not_found`]
- [Organizacija: npr. Arrange/Act/Assert ili Given/When/Then]
- [Šta se testira: npr. svaki public endpoint, business logika u servisima]
- [Šta se NE testira: npr. trivijalni getter-i, framework kod]

## API

- [Stil: npr. REST, GraphQL]
- [Verzioniranje: npr. `/api/v1/`, header-based]
- [Response format: npr. `{ data, error, meta }`]
- [Pagination: npr. cursor-based, offset-based]
