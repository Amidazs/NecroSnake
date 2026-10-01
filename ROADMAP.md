# NecroSnake Roadmap

**Roadmap baseline:** 1 October 2026  
**Canonical recovery commit:** `d1beef14ee21e0cff523a5de473b91f68d63aa9f`  
**Canonical Studio place:** `place.rbxl`

## Vision

NecroSnake is a third-person dark-fantasy Roblox action/army game with a slightly humorous edge. The player is a dangerous but vulnerable necromancer whose main strength comes from building, commanding, risking, losing, recovering, and evolving an undead army.

The core loop is:

**Enter Arena -> fight -> create corpses -> actively attempt raises -> grow/customise army -> fight players and factions -> extract valuable survivors -> preserve selected units in the Base -> clone/rebuild -> risk them again.**

PvP is the centre of the game. PvE factions, bosses, collection, cloning, events, army customisation, and progression all exist to make PvP decisions more interesting.

## Locked Game Rules

### Camera and player role

- Normal third-person Roblox camera.
- Player jumping is disabled; traversal/combat must not allow terrain-jump cheese against melee enemies.
- The necromancer is personally dangerous but vulnerable.
- The army is the player's main source of battlefield power.
- A necromancer caught alone should be at serious risk.
- The player eventually equips a maximum of **3 Necromancer skills**.
- Skills can only be changed at the Base.
- Level 1 begins with no equipped skill slots.
- Skill slots unlock progressively; current target is approximately Level 10 / 25 / 50 for slots 1 / 2 / 3, subject to balance testing.

### Army scale and capacity

- The long-term fantasy is **several hundred individual undead**.
- Units remain individual rather than being represented as stacks.
- Necromancer level increases Command Capacity.
- Early progression target: Level 1 ~= 5 capacity, Level 2 ~= 10, then continued growth toward several hundred capacity at high level.
- Capacity is weighted.
- Weak basic units may cost 1 capacity.
- Armour, cavalry, giants, elites and bosses cost progressively more.
- Only **1 major boss-class unit** may be deployed per army initially.
- Rebirth will provide long-term progression without simply multiplying raw PvP damage.

### Army control and formations

- Army AI is not fully autonomous; the player must have meaningful tactical control.
- Core battlefield commands: **Follow/Regroup, Move Here, Hold Position, Attack Target, Retreat**.
- Players can organise units into tactical cohorts.
- Initial cohort concepts: Frontline, Second Line, Ranged, Left Flank, Right Flank, Rear Guard and Personal Guard.
- The Base contains a Formation Editor.
- Example: Armoured Skeletons in front, spearmen behind them, archers behind those, cavalry on the flanks.
- Formation presets should be switchable in combat without individual-unit micromanagement.

### Corpses and raising

- Raising is an active action, not automatic.
- A corpse exists for approximately **20 seconds** by default.
- The killer has exclusive raise rights for the first **6 seconds**.
- After 6 seconds, any eligible necromancer may attempt to raise it.
- At approximately 20 seconds, an unraised corpse/soul disappears.
- Boss corpse lifetime may be longer if testing shows that is needed.
- Raise attempts have a chance to fail.
- Raise chance improves as the Necromancer progresses.
- Raise speed and raise reach may also improve with progression.
- Every corpse has a maximum of **3 failed Raise attempts total**, shared across all players.
- On the third failed attempt, the corpse/soul collapses and disappears immediately.
- A failed attempt does not automatically prevent a later attempt if failures remain and the corpse timer has not expired.
- Failure state should be readable visually: stable -> damaged/unstable -> critical -> soul collapse.
- Once dead, a raisable corpse is protected from normal combat damage and active NPC/army cleanup until it is Raised, collapses, or expires.
- Raisable corpses become completely inert on death: no AI movement, no residual MoveTo motion and no physics drift.
- If an **NPC unit delivers the final blow**, the victim disappears immediately and creates no raisable corpse at all.
- A Necromancer may **never Raise their own fallen undead**, even after another player's Soul Claim window has expired.
- Even high-level Necromancers should not reach guaranteed capture rates for the rarest elites/bosses.

### Full army behaviour

- A Raise cannot begin unless enough Command Capacity is available.
- Trying to raise while full consumes **no Raise attempt**.
- The UI must explain why the Raise cannot start and show required vs available Command Capacity.
- The corpse timer continues while the player's army is full.
- Players may **Banish** their own deployed undead to free capacity.
- Banish has a visible HUD button as well as the keyboard/controller binding.
- Banish permanently destroys that deployed unit.
- Banished units leave no raisable corpse.
- Units cannot be safely returned to the Base/backpack while remaining in the Arena.

### PvP death and corpse theft

- Arena PvP is always active.
- Individual undead killed in PvP can become raisable corpses.
- If the Necromancer dies, the player's entire deployed army is lost from their ownership.
- Those dead/lost units may be raised by other Necromancers while their corpses remain valid.
- A successfully raised enemy unit joins the new owner's army **immediately on the battlefield**.
- PvP should visibly swing as players raise each other's casualties.
- Extraction is the only reliable way to secure valuable battlefield gains.

### Permanent collection and Soul Imprints

- The Base contains Soul Imprinting / cloning machinery.
- An extracted individual unit can be placed into a chamber as a **Master**.
- A Master is preserved and can produce exact physical clones over time.
- Cloning costs both **time and Soul Essence/resource**.
- Production continues offline while resources are available.
- Each cloning machine has a finite output/storage cap.
- Base upgrades can increase machine count, capacity, output storage and/or efficiency.
- A Master may be removed from safety and deployed again.
- If a removed Master dies and is not recovered, the player permanently loses that Master.
- This enables deliberate high-risk evolution attempts.
- A clone that undergoes a meaningful transformation may itself be extracted and registered as a new Master.
- Clones are normal individual units once deployed: they can die, be stolen, raised or lost.

### Evolutions and world events

- Events/regions may transform surviving undead into rare variants.
- Example: a Giant taken into a lightning event may become a **Stormcharged Giant** if the transformation succeeds.
- Transformation attempts should involve danger, not passive waiting.
- Potential future mutation families include Stormcharged, Bloodbound, Ashforged, Frostbitten, Plagueborn, Fallen/Hallowed and Shadowtouched.
- The player should often choose between keeping a valuable Master safe or risking it for a stronger/rarer evolution.

### Factions and bosses

- The Arena contains living factions that fight each other without player involvement.
- Factions should provide distinct army identities and unit roles.
- Players can deliberately hunt particular factions to customise army composition.
- Bosses can be raised and permanently owned.
- Boss abilities used against the player translate into abilities used while the boss is owned.
- Bosses have high Command Capacity cost, long clone times and a one-major-boss deployment limit initially.

### Servers, matchmaking and friends

- Initial Arena target: **8 Necromancers per server**.
- Normal matchmaking should quietly consider Command Capacity, Rebirth tier and eventually loadout/recent PvP strength.
- Matchmaking should not feel like a rigid visible ranked ladder.
- Players may explicitly join friends even when the friend's server is above/below their normal matchmaking band.
- Joining a stronger friend's server means accepting the higher risk.
- Future parties should match primarily using the strongest/highest-band player to prevent smurfing into beginner servers.
- Trading is **not planned for initial release**.

## Phase 0 - Recovery and consolidation - COMPLETE

Completed on 1 October 2026.

- Recovered latest Feb 18 source.
- Consolidated old playable Workspace shell with recovered systems.
- Added canonical `place.rbxl`.
- Restored seven current unit templates and the Yasu foliage pack.
- Fixed Rojo StarterPlayerScripts mapping.
- Restored/ported player Bone Sword combat into the Humanoid-based recovered backend.
- Verified 3 Skeleton starter army.
- Verified NPC battlefield population and AI startup.
- Verified Bone Sword kill -> last-hit attribution -> Raise success.
- Verified Arena -> Sanctum -> backpack -> Arena redeployment.
- Verified cold-open playtest from tracked `place.rbxl`.
- Recovery baseline is committed in Git.

## Phase 1 - Core combat and active necromancy

**Status:** IN PROGRESS - active necromancy mechanics + presentation foundation GREEN on 1 October 2026; hands-on fun/feel review still pending.

**Goal:** make killing one enemy and raising it feel good enough to support the entire game.

Work:
- [x] Replace automatic corpse raising with active raising.
- [x] Add corpse state and 20-second lifetime.
- [x] Add killer-only 6-second Soul Claim window.
- [x] Add 3-failure corpse attempt state.
- [x] Add raise chance calculation based on unit difficulty + Necromancer progression hook.
- [x] Remove prototype "always raise" behaviour from bosses.
- [x] Add weighted Command Capacity costs to current unit types/variants.
- [x] Add capacity check before Raise begins.
- [x] Add clear "Army Full / Need X Capacity" feedback.
- [x] Add Banish command for living owned units.
- [x] Prevent Banish from deleting dead/raisable owned corpses.
- [x] Protect raisable corpses from repeated combat hits and NPC/group cleanup by moving them into a dedicated corpse lifecycle container.
- [x] Prevent owners from Raising their own fallen undead at any point in the corpse lifetime.
- [x] Disable player jumping on both server and client to prevent terrain-jump combat cheese.
- [x] Add Raise targeting/interaction UI using a hold-to-Raise ProximityPrompt.
- [x] Add Command Capacity HUD readout.
- [x] Add basic corpse failure readability (green -> amber -> red Highlight states).
- [x] Add dedicated Raise channel animation.
- [x] Add Raise success/failure VFX and audio.
- [x] Improve corpse decay/disintegration presentation beyond the current Highlight placeholder.
- [x] Improve player attack animation and weapon feel.
- [x] Add enemy hit reaction and death presentation.
- [x] Improve own-army visual identification.
- [x] Run the technical 5 -> 20 army-growth/readability test after the presentation pass; subjective fun/feel remains for hands-on player review.

**Acceptance / playtest status:**
- [x] Player can deliberately kill, target and attempt to raise a corpse.
- [x] Raise can succeed or fail.
- [x] Three failed attempts destroy the corpse.
- [x] Full army blocks Raise without consuming an attempt.
- [x] Banish frees Command Capacity.
- [x] A newly freed capacity slot allows a previously impossible unit type to be Raised.
- [x] Killer exclusivity blocks another player identity during the first 6 seconds without consuming an attempt.
- [x] After the 6-second claim window expires, the corpse becomes eligible to other Necromancers.
- [x] Corpse disappears after approximately 20 seconds if left unraised.
- [x] Dead owned units cannot be Banished to deny corpse theft.
- [x] Clean restart: Level 1 starts at 5 Command, 3 starter Skeletons use 3/5, Raise bonus starts at 0.
- [x] Clean restart produced no runtime errors after the Phase 1 final marker.
- [ ] Growing from roughly 5 -> 20 units is already satisfying without relying on meta progression.

**1 October 2026 test evidence:**
- Dark Knight at 3/5 Command correctly refused Raise because it required 3 additional Command; failures remained 0.
- Banish removed one living Skeleton without leaving a corpse and reduced usage from 3/5 to 2/5.
- Fresh Dark Knight then Raised successfully and filled capacity to 5/5.
- 5% Grave Baron test failed three consecutive Raise attempts and collapsed on the third; the Raise prompt locked immediately so no fourth/race-window attempt was possible.
- Simulated foreign Soul Claim blocked Raise with failures remaining 0; the same corpse became raisable after claim expiry.
- Untouched corpse expired and disappeared after the 20-second lifetime.
- Dead starter Skeleton rejected Banish and remained a valid corpse.
- End-to-end Bone Sword test confirmed: player attack killed a controlled Weak Skeleton, the corpse remained without auto-raising, the active Raise prompt appeared, and a successful Raise added the unit to the army and updated Command Capacity.
- Bone Sword presentation test confirmed the avatar's ToolSlash animation runs at Action priority, the sword Trail is active during the swing, and confirmed hits drive a crosshair hit marker plus target flash.
- Confirmed-hit test reduced a controlled target from 100 -> 82 HP while the client showed the validated hit flash.
- Raise-channel presentation test confirmed the avatar's Cheer animation runs at Action priority during the hold and a growing necromantic soul focus appears above the corpse.
- Corpses now emit persistent soul particles/light while raisable; failure state recolours the soul effect as well as the corpse Highlight.
- Real 20-second expiry test confirmed the corpse enters a fade/disintegration state (about 70% transparent, particles stopped) before being removed instead of popping out instantly.
- Successful Raise now spawns the owned unit at the dead unit's corpse position; final test placed the new Weak Skeleton within about 1.7 studs of the post-death corpse pivot before normal army AI movement.
- Technical army-growth test reached 20 live individually owned units at 20/25 Command; all 20 had friendly-identification outlines and naturally spread about 7-20 studs around the Necromancer.
- Visual capture review found the first cyan outline treatment too debug-like; it was replaced by a softer occluded necromantic-green outline with reduced fill/opacity for better readability at 20 units.
- Corpse-protection regression test used a real NPC-group unit: after death it moved to `Workspace.Corpses`, survived multiple NPC cleanup cycles, survived another Bone Sword swing, remained at 0 HP, and retained 0 Raise failures.
- Own-fallen-unit test confirmed the owner receives `You cannot Raise your own fallen undead.` immediately and again after the 6-second Soul Claim expires; the corpse remains available to other eligible Necromancers and the owner's failed-attempt count stays unchanged.
- No-jump test confirmed client and server both report Jumping disabled, AutoJump off, JumpPower/JumpHeight at 0; forced client jump/state-change attempts produced effectively zero upward movement and the Humanoid remained in Running state.

**Next Phase 1 slice:** hands-on player feel review of combat/Raise feedback and 5 -> 20 army growth remains open while Phase 2 command work proceeds; address feel issues before declaring Phase 1 formally complete.

## Phase 2 - Tactical army control and formations

**Status:** IN PROGRESS - whole-army command foundation GREEN on 1 October 2026.

**Goal:** make the player feel like an army commander rather than a pet owner.

Work:
- [ ] Introduce cohorts/formations.
- [ ] Frontline / Second Line / Ranged / Flanks / Rear Guard / Personal Guard.
- [ ] Formation Editor in Base.
- [ ] Save formation assignments.
- [x] Follow/Regroup.
- [x] Move Here.
- [x] Hold Position.
- [x] Attack Target.
- [x] Retreat.
- [ ] Formation switching in combat.
- [ ] Per-cohort behaviour where useful.
- [ ] Better spacing, local avoidance and anti-pile-up.

**Command foundation test evidence:**
- Hold kept a three-unit army at its commanded location while the player moved about 28 studs away.
- Follow regrouped the army back to within about 1 stud of the player.
- Move Here moved the army roughly 22 studs to the commanded point and automatically changed to Hold on arrival.
- Attack Target kept the army focused on the selected controlled target and reduced it from 400 to 390 HP with `PLAYER_ARMY` final-damage attribution.
- Retreat broke the attack command, reduced army/player separation from about 38 studs to about 4.6 studs, then automatically restored Follow.
- Command UI exposes Follow -> Move Here -> Hold -> Attack Target -> Retreat in a fixed order without selecting individual units.
- Visible Banish button was repositioned above the Veil Gate panel after visual QA; the `B` shortcut remains available.
- Static-corpse regression test showed 0 studs movement and 0 velocity after death.
- Real NPC final-blow test destroyed a 1-HP owned unit on the next NPC attack cycle with no entry created in `Workspace.Corpses`.

**Acceptance:**
- Player can build a shield-front / ranged-rear formation.
- Formation remains understandable while moving and fighting.
- Commands work without selecting hundreds of individual units.
- A player can intentionally screen archers with armoured melee units.

## Phase 3 - Scale to several hundred undead

**Goal:** make the target army scale technically viable before adding lots of content.

Technical direction:
- Cohort-level movement decisions.
- Lightweight local steering for members.
- Avoid individual expensive pathfinding wherever possible.
- Budget combat/target updates across frames.
- Distance-based AI update rates.
- Animation/visual LOD.
- Reduced simulation for distant irrelevant fights.
- Network ownership/replication review.
- Pooling where useful.

Stress gates:
- 25 owned units.
- 50 owned units.
- 100 owned units.
- 200 owned units.
- 300 owned units.
- Multiple players plus active NPC factions.

**Acceptance:**
- Large armies remain responsive and readable.
- Server frame time and network use remain within acceptable limits.
- No catastrophic pile-up, pathfinding or replication failure.

## Phase 4 - PvP rules and battlefield theft

**Goal:** make army-vs-army PvP the central source of tension.

Work:
- Dedicated two-player PvP acceptance tests.
- Corpse Soul Claim ownership.
- Enemy-unit raising during active PvP.
- Necromancer death -> deployed army loss.
- Lost units become battlefield opportunities.
- Spawn protection.
- Combat logging/logout rules.
- Kill attribution.
- Anti-safe-zone abuse.
- Threat/scouting UI.
- Approximate enemy level/rebirth/army threat readability.

**Acceptance:**
- Two players can fight, lose units, steal casualties and reverse momentum through raising.
- Killing the Necromancer produces a meaningful but performant corpse/recovery event.
- Death cannot be trivially exploited by logging/rejoining.

## Phase 5 - Permanent collection, Masters and cloning

**Goal:** create long-term ownership without removing battlefield risk.

Work:
- DataStore-backed individual unit collection.
- Master/Soul Imprint records.
- Put unit into cloning chamber.
- Remove Master from chamber and risk it.
- Soul Essence/resource economy.
- Clone timers.
- Offline production.
- Machine output caps.
- Multiple machine support.
- Base machine upgrades.
- Exact preservation of template/size/trait/evolution/ability data.
- Safe save/retry/versioning strategy.

**Acceptance:**
- Extracted unit can become a permanent Master.
- Player can leave the game and return without losing the Master.
- Cloning progresses offline only while allowed by resource/storage rules.
- Player can deploy a clone and lose it without deleting the Master.
- Player can deliberately remove and permanently risk the Master.

## Phase 6 - Necromancer levels, capacity, skills and Rebirth

**Goal:** create clear long-term progression without making veteran PvP automatically unbeatable.

Work:
- Necromancer XP and levels.
- Command Capacity progression.
- Raise proficiency progression.
- Raise speed/reach progression where appropriate.
- Weighted unit capacity.
- Skill-slot unlocks.
- Maximum 3 equipped Necromancer skills.
- Skill loadout changed only at Base.
- Initial skills: Bone Wall, Fear Pulse, Rally, Corpse Explosion, Regroup, Sacrifice/Frenzy candidates.
- Rebirth system.
- Rebirth rewards focused on options/prestige/base progression rather than huge raw damage multipliers.

**Acceptance:**
- Level progression visibly expands army possibilities.
- Level 1 works with a small army and no active skill slots.
- Higher levels allow larger/more specialised compositions.
- Rebirth is desirable without making new-player PvP pointless.

## Phase 7 - Factions and army identity

**Goal:** turn PvE into a source of strategically different army components.

Work:
- Multiple autonomous factions.
- Faction-vs-faction conflicts.
- Distinct unit roles: shields, spears, archers, cavalry, casters, brutes, support, etc.
- Region/faction spawn identities.
- Unit readability at distance.
- Undead versions retain combat role.
- Faction-specific rare/elites.

**Acceptance:**
- Two players at the same capacity can deliberately build visibly different armies.
- Watching an NPC faction battle should create useful corpse opportunities even without player initiation.

## Phase 8 - Boss ownership and elite encounters

**Goal:** make bosses aspirational army prizes, not only loot sources.

Work:
- Boss ability framework shared between enemy and owned state.
- Boss Raise difficulty.
- Boss corpse presentation.
- Boss cloning cost/time.
- One-major-boss deployment restriction.
- Boss command/AI behaviour within formations.
- Boss-specific VFX/readability.

**Acceptance:**
- Defeating and successfully raising a boss produces an owned boss with recognisably the same signature abilities.
- Owned bosses are powerful but do not invalidate army composition.

## Phase 9 - Events and undead evolution

**Goal:** create high-risk ways to transform existing valuable units.

Work:
- Event framework.
- Lightning/storm event prototype.
- Eligible-unit transformation rules.
- Survival/failure risk.
- Master/clone evolution persistence.
- Event telegraphing.
- Limited-time map conditions.

**Acceptance:**
- Player can intentionally bring a valued unit into an event, risk losing it, transform it, extract it and register the transformed unit as a new Master.

## Phase 10 - Proper Arena world and Base

**Goal:** replace the recovery placeholder world with an authored game space.

Arena:
- Multiple faction regions.
- Elevation and sightlines.
- Battles visible in the distance.
- Dangerous high-reward regions.
- PvP ambush/retreat routes.
- Boss/event spaces.

Base:
- Soul chambers/cloning room.
- Formation Editor.
- Skill loadout area.
- Codex.
- Master/unit displays.
- Upgradeable machine/building presentation.
- Boss trophies and cosmetics.

**Acceptance:**
- The world naturally produces decisions about risk, scouting, faction hunting and PvP.
- The Base is useful without becoming where most playtime is spent.

## Phase 11 - Matchmaking, friends and social play

**Goal:** keep always-on PvP viable while preserving Roblox friend play.

Work:
- Background matchmaking bands.
- Capacity/Rebirth/loadout strength inputs.
- 8-player Arena target.
- Join Friend override.
- Party support.
- Strongest-member matchmaking for parties.
- Server hopping protections.
- Friend/party indicators in battle.

**Acceptance:**
- Normal players usually meet reasonably comparable threats.
- Friends can still join one another across progression bands.
- Low-level accounts cannot easily drag veteran armies into beginner servers.

## Phase 12 - Polish, onboarding, analytics and launch preparation

Work:
- Final HUD.
- Mobile/controller support.
- Short tutorial.
- Audio pass.
- Music.
- Resurrection/death/boss VFX polish.
- Accessibility/readability.
- Performance settings.
- Analytics events.
- Retention funnel.
- Soft-launch balance.
- Cosmetics-first monetisation.
- No trading at initial release.

Key analytics:
- First kill.
- First Raise attempt.
- First Raise success/failure.
- First army of 10/25/50/etc.
- First PvP encounter.
- First PvP kill/death.
- First extraction.
- First Master imprint.
- First clone.
- First boss capture.
- Session length, D1/D7 retention, extraction rate and average peak army capacity.

## Immediate next milestone

**Continue Phase 1: presentation and combat feel.**

The active Raise rules are implemented and playtested. The next slice is:
1. Add a dedicated Necromancer Raise/channel animation.
2. Add visible soul/VFX movement from corpse to Necromancer/army on success.
3. Add clear failure and third-failure soul-collapse VFX.
4. Improve corpse decay/disintegration presentation.
5. Improve Bone Sword attack animation and hit feel.
6. Add enemy hit reactions and better death presentation.
7. Review own-army readability in a growing crowd.
8. Run a 5 -> 20 army-growth playtest and fix anything that makes growth feel unclear or unsatisfying.

No major new faction, boss, permanent-progression, Base or world-content work should begin until this Phase 1 loop is fun and reliable.
