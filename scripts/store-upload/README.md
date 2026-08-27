# store-upload

Garmin ships no publishing API, so this drives the Connect IQ developer
dashboard with Playwright against the locally installed Chrome. It exists to
turn the per-release store upload into one command.

## One-time setup

```sh
cd scripts/store-upload
npm install            # playwright-core only; uses the system Chrome
node upload.mjs login  # opens Chrome; complete SSO + MFA at the keyboard
```

The session is saved to `~/.config/analog-simple/garmin-session.json` —
outside the repo, never committed. When it expires, uploads fail loudly and
you run `login` again.

## Per release

```sh
node upload.mjs list                     # discover the app entries + URLs
node upload.mjs upload --name "Analog Simple" \
    --iq ../../bin/analog-simple-<version>.iq \
    --notes "What's new text" --dry-run  # stops before submit, screenshots
node upload.mjs upload ... # without --dry-run to actually submit
```

## Caveats (eyes open)

- **No API contract.** The selectors are best-effort against dashboard
  markup Garmin can change at will. Every failure saves a screenshot + HTML
  dump into `bin/` so the selectors can be fixed *without* redoing MFA.
- First runs should use `--dry-run` (and `--headed` to watch it work).
- This automates your own account at low volume, but automated logins can
  trip bot detection; it's ToS-gray. Keep it to release uploads.
