# NecroSnake

NecroSnake is a Roblox necromancer battlefield game. The player enters a living
arena with a small undead army, kills hostile units, raises selected corpses,
builds a larger army, and returns survivors to a Sanctum collection.

## Canonical project state

The project was consolidated on 2026-10-01 from the latest recovered
`NecroSnakeNew` source (Feb 18, 2026), the older Studio place, and later local
assets/fixes.

- Canonical Studio place: `place.rbxl`
- Canonical source: `src/`
- Rojo project: `default.project.json`
- Recovery branch: `recovery/feb18-canonical`

Do not use the old Feb 8/9 Studio files or the earlier GitHub layout as the
source of truth.

## Current gameplay loop

- Start with 3 Skeletons in the Arena.
- Roaming NPC groups fight players, armies, and other NPC groups.
- Player army follows, targets, fights, leashes, and forms around the player.
- The player can attack directly with the Bone Sword.
- Last-hit ownership determines who can raise a corpse.
- Raised units preserve their template, size tier, and trait.
- Rare units have lower raise chances; WeakSkeleton and bosses always raise.
- Return to the Sanctum through the Veil Gate.
- Surviving undead are stored in the Army Manager backpack.
- Select/deploy stored undead when entering the Arena again.

## Current unit templates

- WeakSkeleton
- Skeleton
- SkeletonKnight
- ZombieBrute
- DarkKnight
- GraveBaron
- CryptWarden

Source models are tracked under `src/ServerStorage/ModelLibrary`. The Yasu
stylized foliage pack is also tracked under `src/ServerStorage`.

## Important systems

- `ArmyService.lua` — player army ownership, spawning, raising, cleanup.
- `ArmyAIService.lua` — formations, combat targeting, leash/return behavior.
- `NPCService.lua` — living battlefield groups, combat, fleeing, bosses.
- `CombatService.lua` — death hooks and corpse raising.
- `PlayerCombatService.lua` — server-authoritative Bone Sword combat.
- `BackpackService.lua` — Sanctum army storage and Arena loadout.
- `TeleportService.lua` — Arena / Sanctum travel.
- `ArmyRegenService.lua` — army regeneration.
- `WorldBootstrap.lua` — recovered Sanctum and Arena placeholder world.
- `YasusBiomeSpawner.server.lua` — battlefield foliage population.

## Verified recovery playtest — 2026-10-01

A clean Studio playtest of `place.rbxl` verified:

- Correct StarterPlayerScripts execution.
- 3/3 starter Skeletons spawn and survive initial startup.
- Random Arena placement uses the 1960x1960 SpawnBounds correctly.
- Battlefield population reached 146 NPCs in 36 groups during the smoke test.
- Foliage generator successfully placed 900 objects.
- Bone Sword kill -> last-hit attribution -> corpse raise works.
- A WeakSkeleton was killed and raised into the player's army.
- Arena -> 10 second retreat -> Sanctum works.
- The raised unit appeared in Army Manager as `WeakSkeleton x1`.
- Sanctum -> Arena redeployed that stored unit successfully.
- Teleport and Backpack GUIs load and update by zone.

## Known unfinished areas

- Backpack/loadout data is session-only; DataStore persistence is not built.
- Teleport retreat text says "hold still", but movement/damage cancellation is
  not yet enforced.
- Some debug logging/UI flags remain enabled.
- The recovered world is a functional placeholder, not final environment art.
- Two-player PvP still needs a dedicated multiplayer acceptance test.
- Progression, economy, onboarding, VFX/audio polish, and release balancing
  remain future work.

## Development workflow

Install/activate the pinned toolchain, then use Rojo for source synchronization:

1. `aftman install`
2. `rojo serve default.project.json`
3. Open `place.rbxl` in Roblox Studio.
4. Connect the Rojo plugin to the running server.

Workspace is intentionally not mapped by Rojo because the canonical place owns
the recovered Arena/Sanctum world state. Source changes should be made under
`src/`; Studio-only world changes should be saved into `place.rbxl`.

Before merging major work, run at least the core acceptance loop:
spawn -> fight -> raise -> Sanctum -> Army Manager -> redeploy.
