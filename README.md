# Al-Folio Upgrade

Upgrade CLI for al-folio v1.x.

## Commands

- `al-folio upgrade audit`
- `al-folio upgrade apply --safe`
- `al-folio upgrade report`

## What it checks

- Core config contract (`al_folio.*`, Tailwind, Distill)
- Legacy Bootstrap/jQuery markers
- Distill remote-loader policy
- Local override drift when `theme: al_folio_core` is enabled
- Migration manifest availability from `al_folio_core`
