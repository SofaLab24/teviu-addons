# teviu-addons

World of Warcraft addons for **WoW Forever** (client 1.60, `## Interface: 16001`).

| Addon | What it does |
|---|---|
| [Kirilicos Žudikai](addons/KirilicosZudikai/) | Counts your kills (killing blows and assists) of players whose names contain Cyrillic letters. |

## Install (players)

1. Open [Releases](https://github.com/SofaLab24/teviu-addons/releases) and download the addon's zip.
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`. The result must be
   `AddOns/<Addon>/<Addon>.toc`, not a folder inside a folder.
3. Restart WoW and tick the addon in the AddOns list.

## Repository layout

```
addons/<Addon>/      everything that ships: <Addon>.toc, the .lua files, a README
spec/<Addon>/        busted tests for that addon
spec/helpers/        wow_mock.lua, a small fake WoW client the tests run against
.github/workflows/   ci.yml (every push and pull request), release.yml (release tags)
```

## Development

### Tools, once per computer

Tests use [busted](https://lunarmodules.github.io/busted/) and the linter is
[luacheck](https://github.com/lunarmodules/luacheck). GitHub runs both on Lua 5.1, the
version WoW uses, on every push.

| OS | Install |
|---|---|
| Linux (Debian, Ubuntu) | `sudo apt install lua5.1 lua-busted lua-check` |
| Windows | The Linux command inside WSL (`wsl --install` sets up Ubuntu) |
| macOS | `brew install luarocks`, then `luarocks install busted` and `luarocks install luacheck` |

On macOS the tests run on Homebrew's newer Lua. The fake client works on Lua 5.1 to 5.4,
and GitHub still checks Lua 5.1.

### Everyday commands, from the repo root

| Task | Command |
|---|---|
| Lint | `luacheck .` |
| Test everything | `busted` |
| Test one addon | `busted spec/<Addon>` |

On Windows, put `wsl` in front (`wsl busted`), or run them in a WSL terminal.

### Trying a change in the game

Copy `addons/<Addon>` into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the
old copy, and type `/reload` in game. A new addon, a renamed one or a changed `.toc` needs
a full game restart.

To skip the copying, link the folder once instead:
- **macOS or Linux:** `ln -s "$PWD/addons/<Addon>" "<WoW>/_forever_/Interface/AddOns/<Addon>"`
- **Windows:** `mklink /J "<WoW>\_forever_\Interface\AddOns\<Addon>" "<repo>\addons\<Addon>"`.
  A junction needs no admin rights.

### Editor

VS Code offers the recommended extensions when you open the repo:
- Lua (`sumneko.lua`)
- WoW API (`ketho.wow-api`), which gives autocompletion and documentation for the game's API

### Adding an addon

1. Create `addons/<Name>/<Name>.toc` with `## Interface: 16001` and `## Version: 0.1.0`, plus its
   Lua files. The folder and the `.toc` must have the same name.
2. Add `spec/<Name>/<Name>_spec.lua`. The existing spec shows how to load an addon in the fake client.
3. In `.luacheckrc`, add a `files["addons/<Name>/**/*.lua"]` entry for the addon's own globals,
   and add any new WoW API it reads to `read_globals`.
4. Add a row to the table at the top of this README.

### Releasing

1. Set `## Version: 1.2.0` in `addons/<Addon>/<Addon>.toc` and commit.
2. Tag that commit and push the tag:
   ```
   git tag <Addon>-v1.2.0
   git push origin <Addon>-v1.2.0
   ```
3. GitHub then does the rest:
   - checks that the tag matches the `.toc`
   - runs the linter and the tests
   - builds `<Addon>-1.2.0.zip` and publishes it on the Releases page, with that addon's commits as the notes

   A version like `1.2.0-beta1` becomes a pre-release.

Every push to `main` also builds zips of all addons. Find them under the run's **Artifacts**
on the Actions tab (you need to be signed in to GitHub).

The [BigWigs packager](https://github.com/BigWigsMods/packager) is the usual release tool for
repos with a single addon. In a repo with several addons, it takes the version and changelog
from the whole repository. So this repo uses a small release workflow instead, as
[forever-addons](https://github.com/matejkadlec/forever-addons) does. An addon that needs
libraries such as Ace3 can still switch to the packager later.
