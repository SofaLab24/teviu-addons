# teviu-addons: notes for Claude

These are WoW addons for **WoW Forever**: flavor folder `_forever_`, client 1.60.x, `## Interface: 16001`, `WOW_PROJECT_ID` 18.
README.md covers the layout, setup, releasing and how to add an addon. Keep it up to date when any of those change.

## Workflow

- **Branches:** every change goes on its own branch (`feature/<topic>` or `fix/<topic>`). Push the branch and offer a pull request. Never commit to `main`; the user merges.
- **Layout:** `addons/<Addon>/` holds only the files that ship. Tests live in `spec/<Addon>/`, and the fake client is `spec/helpers/wow_mock.lua`.
- **After every change,** run both from the repo root, on this Windows machine through WSL:
  - `wsl luacheck .`, which must report 0 warnings
  - `wsl busted`, which must pass
- **Trying it in game:** copy the changed addon into the user's AddOns folder, then tell the user `/reload`. A new addon, a renamed one or a changed `.toc` needs a full restart. The local path and the copy steps are in your memory.
- **Releases:** set `## Version` in the `.toc`, commit, then tag `<Addon>-v<version>`. `.github/workflows/release.yml` checks the tag, tests, zips, and publishes a GitHub Release. Tags publish publicly, so only push one when the user asks.

## Before building something new

Look up how other WoW addon projects solve it before choosing an approach: other addons' code, Warcraft Wiki, the BigWigs packager docs. Bring a short plan with the evidence to the user before writing code.

## WoW Forever API rules (checked against client 1.60.1, Nov 2026)

- **No combat log.** Addons can't use `COMBAT_LOG_EVENT_UNFILTERED` or `CombatLogGetCurrentEventInfo` (Midnight-era rules). Registering CLEU can get the addon blocked, so never use it.
- **Kill and death events:** use the standalone events `PARTY_KILL` (attackerGUID, targetGUID) and `UNIT_DIED` (guid).
- **Honor credit:** `CHAT_MSG_COMBAT_HONOR_GAIN`. Parse it with the `COMBATLOG_HONORGAIN*` format strings, not hard-coded English.
- **Secret values:** any value can be "secret". Check `issecretvalue(v)` before comparing, testing, concatenating or using it as a table key, and wrap API calls in `pcall`.
- **Names are "First Last".** The space is part of the name, and chat links have no realm suffix.
  - `UnitName` can return only the first word.
  - Prefer `GetPlayerInfoByGUID` (6th return is the name, 8th is the level on Forever) or `GetUnitName(unit, false)`.
- **Fonts:** use the game's font objects (`GameFont*`). They include Cyrillic; raw font files may not.
- **Backgrounds:** `Interface\DialogFrame\UI-DialogBox-Background` is see-through on Forever. Use `Interface\Tooltips\UI-Tooltip-Background` with a dark backdrop colour.
- **Sources:** base designs on Blizzard events and on evidence (other addons' code, saved variables, wiki). Don't copy other addons' guesses.

## Code and repo conventions

- **Lua 5.1 in `addons/`:** no `goto`, `//`, bit operators or integer division. Specs and the mock may use anything that runs on Lua 5.1 to 5.4.
- **Settings:** a new user setting gets a default in the addon's defaults table and a row on its Options page (Blizzard's Settings API, as in `addons/KirilicosZudikai/Settings.lua`). Change it with the addon's `SetOption`, so the page and the slash commands stay in step.
- **Guild messages:** one short message per update, with an addon-specific prefix (16 characters at most). Pace them well under the game's limit (10 at once, then 1 a second). Each player sends only their own data, never relays others', and every incoming field is validated.
- **Raid markers:** `SetRaidTarget` is protected (since 12.0). Draw your own icon instead.
- **luacheck:** every addon gets its own `files["addons/<Addon>/**/*.lua"]` block in `.luacheckrc` listing its globals. New WoW API goes in `read_globals`.
- **Tests:** add a spec for every behaviour change. Extend `spec/helpers/wow_mock.lua` when an addon needs more of the API.
- **The repo is public.** No real player names, character names, local paths or other personal data in code, tests or docs; use invented names.
