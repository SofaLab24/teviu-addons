# Kirilicos Žudikai

Counts your kills of players whose names contain Cyrillic letters (Russian, Ukrainian,
Belarusian, Bulgarian, Serbian and so on). Made for WoW Forever.

## Install

Download `KirilicosZudikai-<version>.zip` from the
[Releases page](https://github.com/SofaLab24/teviu-addons/releases) and unzip it into
`World of Warcraft/_forever_/Interface/AddOns/`, so you get `AddOns/KirilicosZudikai/KirilicosZudikai.toc`.
Restart WoW.

**Updating from "KirlicosZudikai" (1.0.0):** the addon was renamed in 1.1.0. Delete the old
`AddOns/KirlicosZudikai` folder first. If both are installed, every kill is counted twice.

## What counts

- **Killing blow:** you land the killing blow on such a player.
- **Assist:** the game gives you honorable-kill credit for such a player ("X dies, honorable kill").

Both count as a kill. One death that produces both counts once, as a killing blow.
In battlegrounds the game gives credit to everyone nearby, so assists add up quickly there.

On a kill you get a chat line and a sound, and the on-screen counter flashes.

## Commands

| Command | What it does |
|---|---|
| `/kz` | Open or close the kill list (players, recent kills) |
| `/kz hud` | Show or hide the on-screen counter (drag it to move it) |
| `/kz sound` | Turn the kill sound on or off |
| `/kz chat` | Turn the chat line on or off |
| `/kz status` | Your totals and what the game reported this session |
| `/kz test` | Self-check and a sample kill (nothing is saved) |
| `/kz reset confirm` | Delete this character's kills |

Kills are saved per character in WoW's own `WTF` folder, not in the addon folder.
