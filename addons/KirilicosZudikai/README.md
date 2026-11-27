# Kirilicos Žudikai

Counts your kills of players whose names contain Cyrillic letters (Russian, Ukrainian,
Belarusian, Bulgarian, Serbian and so on), marks those players when they come near, and keeps
a guild leaderboard. Made for WoW Forever.

## Install

Download `KirilicosZudikai-<version>.zip` from the
[Releases page](https://github.com/SofaLab24/teviu-addons/releases) and unzip it into
`World of Warcraft/_forever_/Interface/AddOns/`, so you get `AddOns/KirilicosZudikai/KirilicosZudikai.toc`.
Restart WoW.

**Updating from "KirlicosZudikai" (1.0.0):** the addon was renamed in 1.1.0. Delete the old
`AddOns/KirlicosZudikai` folder first. If both are installed, every kill is counted twice.

## What counts as a kill

- **Killing blow:** you land the killing blow on such a player.
- **Assist:** the game gives you honorable-kill credit for such a player ("X dies, honorable kill").

Both count as a kill. One death that produces both counts once, as a killing blow.
In battlegrounds the game gives credit to everyone nearby, so assists add up quickly there.

On a kill you get a chat line and a sound, and the on-screen counter flashes.

## Nearby Cyrillic enemies

When an enemy-faction player with a Cyrillic name gets a nameplate near you:
- a **skull** appears above their nameplate. It is the addon's own icon, which only you
  see. Addons can't place the group's real raid marker since patch 12.0.
- an **alert** shows: centre-screen text, a chat line and a sound. Each player alerts at most
  once every 5 minutes (you can change that in the settings).

In battlegrounds you get skulls but no alerts, unless you switch alerts on there. This only
works for players within nameplate range, with enemy nameplates switched on (V key).

## Guild leaderboard

The **Guild** tab in the kill list (`/kz guild`) ranks guildmates who use version 1.2.0 or
newer by kills, with killing blows, this week's kills and when each one last reported in.
Each player sends only their own totals to the guild. You can switch that off in the
settings; guildmates then keep the last numbers they got from you. The numbers are
self-reported, like on any addon leaderboard.

## Settings

Esc > Options > AddOns > Kirilicos Žudikai, or `/kz settings`, or the Settings button in the
kill list.

## Commands

| Command | What it does |
|---|---|
| `/kz` | Open or close the kill list (Players, Recent kills, Guild) |
| `/kz guild` | Open the guild leaderboard |
| `/kz settings` | Open the settings |
| `/kz hud` | Show or hide the on-screen counter (drag it to move it) |
| `/kz sound` | Turn the kill sound on or off |
| `/kz chat` | Turn the kill chat line on or off |
| `/kz alert` | Turn alerts for nearby Cyrillic enemies on or off |
| `/kz skull` | Turn the skulls above their nameplates on or off |
| `/kz status` | Your totals and what the game reported this session |
| `/kz test` | Self-check, a sample kill and a sample alert (nothing is saved) |
| `/kz reset confirm` | Delete this character's kills |

Kills are saved per character in WoW's own `WTF` folder, not in the addon folder.
