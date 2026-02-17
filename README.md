# Al-Folio Upgrade

Upgrade CLI for al-folio v1.x.

## Commands

- `al-folio upgrade audit`
- `al-folio upgrade apply --safe`
- `al-folio upgrade report`

## What it checks

- Core config contract (`al_folio.*`, Tailwind, Distill)
- Required plugin ownership wiring (for example `al_icons`)
- Legacy Bootstrap/jQuery markers
- Distill remote-loader policy
- Local override drift when `theme: al_folio_core` is enabled
- Plugin-owned local asset drift (for example search/icon runtime files copied into starter paths)
- Migration manifest availability from `al_folio_core`
