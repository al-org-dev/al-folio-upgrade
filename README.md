# al-folio-upgrade

`al_folio_upgrade` is the upgrade CLI for `al-folio` v1.x.

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
- Plugin-owned local asset drift (for example copied search/icon runtime files)
- Migration manifest availability from `al_folio_core`

## Ecosystem context

- Starter execution/docs live in `al-folio`.
- Upgrade policy/audit behavior is owned by this plugin.

## Contributing

Audit/apply/report logic updates should be proposed in this repository.
