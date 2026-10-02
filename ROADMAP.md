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

**Status:** COMPLETE - mechanically GREEN and hands-on mixed-combat readability/feel accepted on 1 October 2026.

**Goal:** make the player feel like an army commander rather than a pet owner.

Work:
- [x] Introduce cohorts/formations.
- [x] Frontline / Second Line / Ranged / Flanks / Rear Guard / Personal Guard.
- [x] Formation Editor in Base.
- [x] Save template -> cohort formation assignments using a versioned formation profile DataStore; unpublished Studio uses a session-only fallback.
- [x] Follow/Regroup.
- [x] Move Here.
- [x] Hold Position.
- [x] Attack Target.
- [x] Retreat.
- [x] Formation switching in combat with Standard / Defensive / Aggressive / Compact presets.
- [x] Per-cohort positioning for Follow / Move Here / Hold / Retreat plus engine-side combat behaviour for Frontline / Ranged / Rear Guard / Flanks / Personal Guard.
- [x] Better spacing, lightweight local separation/anti-pile-up, and stuck-unit watchdog recovery.

**Command foundation test evidence:**
- Hold kept a three-unit army at its commanded location while the player moved about 28 studs away.
- Follow regrouped the army back to within about 1 stud of the player.
- Move Here moved the army roughly 22 studs to the commanded point and automatically changed to Hold on arrival.
- Attack Target kept the army focused on the selected controlled target and reduced it from 400 to 390 HP with `PLAYER_ARMY` final-damage attribution.
- Retreat broke the attack command, reduced army/player separation from about 38 studs to about 4.6 studs, then automatically restored Follow.
- Command UI exposes Follow -> Move Here -> Hold -> Attack Target -> Retreat in a fixed order without selecting individual units.
- Visible Banish button was repositioned above the Veil Gate panel after visual QA; the `B` shortcut remains available. The current-build Banish path removed the aimed owned unit, updated Command Capacity from 3/5 to 2/5, and returned the correct success feedback.
- Static-corpse regression test showed 0 studs movement and 0 velocity after death.
- Real NPC final-blow test destroyed a 1-HP owned unit on the next NPC attack cycle with no entry created in `Workspace.Corpses`.

**Cohort formation test evidence:**
- Existing/newly owned units receive a `Cohort` attribute from their template default; tested defaults are Weak Skeleton/Skeleton -> Second Line, Skeleton Archer -> Ranged, Skeleton Knight/Zombie Brute/Dark Knight -> Frontline, and Grave Baron/Crypt Warden -> Personal Guard.
- Formation panel exposes all six cohorts with live counts and allows the player to aim at an owned living unit and reassign its cohort; the server validates ownership before applying the change.
- Mixed-cohort Hold test placed Frontline about 12.6 studs ahead, Ranged about 8.4 studs behind, and Personal Guard about 2.3 studs close behind the anchor.
- The same mixed formation preserved those bands after a Move Here command; on arrival the army automatically returned to Hold.
- Follow test after moving the Necromancer kept Flanks about 11.4 studs to the side, Second Line about 7.1 studs ahead, and Rear Guard about 13.5 studs behind.
- Formation UI visual QA confirmed the panel is readable above the command bar and the tactical order is fixed as Frontline -> Second Line -> Ranged -> Flanks -> Rear Guard -> Personal Guard.
- Base Formation Editor is available only inside the Sanctum/SafeZoneRegion; the same template-edit request is server-rejected from the Arena.
- Base editor lists every current ModelLibrary template, its catalogue default cohort, and any saved override; Reset returns a template to its catalogue default.
- Template rule test changed `Skeleton -> Ranged` in the Sanctum and immediately updated all three existing Skeletons to Ranged.
- Respawn inheritance test then cleared the old army and spawned new starter Skeletons (ArmyUnitIds 4-6); all three inherited Ranged from the Base profile rather than the catalogue Second Line default.
- Arena edit test attempted `Skeleton -> Frontline` and was rejected with `Formation defaults can only be edited in the Sanctum`; the live units remained Ranged.
- Unpublished Studio safely uses a session-only formation-profile fallback because Roblox DataStore access requires a published place; published servers use `NecroSnakeFormationProfile_v1` and save template -> cohort overrides.
- Test overrides were reset before saving the canonical place; live Skeletons returned to the catalogue `SecondLine` default.
- Combat preset test confirmed the formation physically reshapes rather than only changing UI state: Standard Frontline ~14.8 studs ahead / Ranged ~6.1 behind / Personal Guard ~2.2 close; Defensive pulls Frontline back to ~11.8 and Ranged to ~7.9; Aggressive pushes Frontline to ~17.1 while Ranged advances to ~5.5; Compact tightens Frontline to ~9.7.
- Temporary ranged-contract validation (`AttackRange = 24`, `PreferredRange = 18`) held a Ranged test unit at ~19.8 studs while it continued damaging the selected target; when the target moved, the unit stayed just inside its 24-stud attack range instead of collapsing into melee.
- Personal Guard combat validation confirmed it stays with the Necromancer when an explicit Attack Target is beyond the 20-stud guard-engage radius, while Frontline and Ranged continue the attack.
- Pile-up validation deliberately stacked three Frontline units on one point; after entering combat they separated to a minimum pair distance of ~2.6 studs and still reduced the dummy target from 3000 to 2970 HP.
- Stuck-unit watchdog validation immobilised a unit ~35.5 studs from the player: the first recovery cycle nudged it to ~34.1 studs and the second hard-recovered it to ~11.3 studs. Formation/cohort changes now reset watchdog progress baselines to avoid false-positive recovery after intentional reshaping.
- `AttackRange` / `PreferredRange` are part of the ModelLibrary stat contract and now power genuine ranged content rather than only temporary validation attributes.
- Added `SkeletonArcher` as a real generated ModelLibrary template with visible bow/quiver treatment, 45 HP, 8 damage, 1.25 s cooldown, 30-stud attack range, 22-stud preferred range, Command Cost 1, `DefaultCohort = Ranged`, and 75% base Raise chance. It automatically participates in ordinary weighted NPC group spawning.
- Fresh-start spawn validation found 26 natural Skeleton Archers in the live battlefield, each carrying the real 30/22 range contract and ranged default cohort.
- Hostile-Archer validation used a natural Archer in a test-runtime non-fleeing group: it dealt an 8-damage ranged hit, emitted arrow tracers, and finished about 21.4 studs from the player against its 22-stud preferred range.
- Capture validation killed and actively Raised two natural Skeleton Archers; both retained `TemplateName = SkeletonArcher`, `Cohort = Ranged`, `AttackRange = 30`, `PreferredRange = 22`, and Command Cost 1 after becoming owned units.
- Real shield-front / ranged-rear combat validation used three captured Skeleton Knights plus two captured Skeleton Archers. Frontline Knights fought at roughly 2.9-5.9 studs while the Archers held roughly 23.3-25.8 studs; the five-unit formation dealt 179 damage during the test window at 8 total Command Capacity.
- The persistent Base Formation Editor already enumerates ModelLibrary templates dynamically, so Skeleton Archer automatically appears there with Ranged as its catalogue default and can receive a saved override like any other template.

**Phase 2 closeout:** hands-on mixed-combat readability/feel review with the real Skeleton Archer was accepted on 1 October 2026. Phase 2 is closed and development proceeds to Phase 3 stress gates (25 -> 50 -> 100 -> 200 -> 300 owned units).

**Acceptance:**
- [x] Player can build a shield-front / ranged-rear formation.
- [x] Formation remains understandable while moving and fighting.
- [x] Commands work without selecting hundreds of individual units.
- [x] A player can intentionally screen archers with armoured melee units.

## Phase 3 - Scale to several hundred undead

**Status:** COMPLETE - 25 / 50 / 100 / 200 / 300 owned-unit gates are GREEN on 1 October 2026. A 600-owned-unit aggregate overload run also completed with live NPC factions as a conservative multi-army load check.

**Goal:** make the target army scale technically viable before adding lots of content.

Technical work:
- [x] Cohort-level target decisions so large cohorts share expensive target scans instead of every unit scanning independently.
- [x] Cached enemy-candidate pools and cached local-separation offsets.
- [x] Budgeted/distance-aware movement updates for medium and distant owned units.
- [x] Staggered NPC target updates plus reduced simulation for distant NPC groups.
- [x] Dynamic NPC population pressure budget while very large owned armies are deployed.
- [x] Shared NPC animation scheduler with distance and density LOD.
- [x] Client-side owned-army VFX/readability LOD.
- [x] Pooled arrow tracers instead of repeated projectile-effect allocation/destruction.
- [x] Client network ownership for owned undead, with server ownership only during stuck recovery.
- [x] Collision-group scaling pass that removes per-unit leader constraint fan-out.
- [x] Large-formation layout/arrival tolerances so Move and Retreat complete reliably with hundreds of units.
- [x] AI/performance instrumentation for owned armies and NPC factions.
- [x] Startup handling for army visual scripts without `WaitForChild` infinite-yield warnings.

Stress gates:
- [x] 25 owned units.
- [x] 50 owned units.
- [x] 100 owned units.
- [x] 200 owned units.
- [x] 300 owned units.
- [x] Aggregate multi-army-equivalent load: 600 owned units plus active NPC factions completed in Play Solo. This is an overload check, not a new 600-unit per-player design target.
- [x] True two-client PvP/network-behaviour testing remains intentionally in Phase 4, where the roadmap already has a dedicated two-player acceptance pass.

**Acceptance:**
- [x] Supported 300-unit armies remain responsive and readable after settling.
- [x] Server-side army/NPC AI work is budgeted and instrumented rather than scaling every expensive decision linearly per unit.
- [x] Network ownership distributes owned-unit physics to the owning client.
- [x] No catastrophic pile-up, pathfinding, command-completion or replication failure was found at the 300-unit target.
- [x] 600 aggregate units completed as an overload test without a fatal runtime failure; expected heavy Play Solo slowdown was recorded rather than treated as a supported target.

**1 October 2026 Phase 3 playtest evidence:**
- Final clean stress run completed all 25 / 50 / 100 / 200 / 300 gates with the exact expected live-unit counts and zero rootless owned units.
- At 300 units, all 300 assemblies were client-owned in the final supported-target run; the active NPC budget settled around 140 units.
- The 300-unit gate recorded owned-army AI at about 33.2 ms average / 53.1 ms max during spawn-and-convergence stress, with NPC AI around 14.4 ms average / 17.6 ms max.
- Once the 300-unit army settled in Hold, a five-second server sample averaged about 26.9 ms per Heartbeat with p95 about 68.6 ms; army AI averaged about 5.4 ms and NPC AI about 15.9 ms in that sample.
- Client Stats during the settled 300-unit run reported about 32.8 average FPS, about 0.9 kB/s send and 130 kB/s receive in Studio, with roughly 3.9 GB total Studio memory. These are Studio measurements, not production-device guarantees.
- Steady-state spacing at 300 units had no unit whose nearest neighbour was under 2 studs; nearest-neighbour distance was about 3.36 studs at p10, 3.89 median and 4.35 at p90.
- All 300 owned units received the friendly army Highlight during the readability check.
- A 300-unit Compact `Move Here` command completed automatically into Hold; army centre finished about 3.24 studs from the requested command point.
- The 300-unit `Attack Target` regression reduced the controlled 1,000,000-HP target, stamped `PLAYER_ARMY` final-damage attribution and exercised the pooled ranged tracer path.
- The 300-unit Retreat regression now returns automatically to Follow; the original all-units-within-18-studs completion rule was replaced for large armies by formation-slot arrival with a 95% threshold.
- The final command/combat console pass had no runtime error and no `PlayerArmies` infinite-yield warnings.
- The saved canonical `place.rbxl` was then cold-opened from disk; the Phase 3 modules/LOD scripts were present, the temporary stress harness was absent, the 3-unit starter army spawned, active NPC factions came online, and the fresh runtime console remained error-free.
- The extra 600-unit aggregate overload run completed with 600 live owned units, 599/600 client-owned assemblies and about 139 active NPCs. Its five-second settled Play Solo sample averaged about 147 ms per Heartbeat, confirming that 600 visible/simulated units in one combined Studio client/server process is an overload condition rather than a supported per-player target.
- The 600-unit run still kept the measured owned-army AI loop around 26.4 ms average and NPC AI around 30.0 ms average after settling, which supports moving true multi-client distribution/transport validation into the dedicated Phase 4 two-player test rather than increasing the per-player target.

## Phase 4 - PvP rules and battlefield theft

**Status:** COMPLETE - two-client PvP, battlefield theft, death loss, combat
logout and 300-unit death-event validation GREEN on 2 October 2026.

**Goal:** make army-vs-army PvP the central source of tension.

Work:
- [x] Dedicated two-player PvP acceptance tests.
- [x] Corpse Soul Claim ownership.
- [x] Enemy-unit raising during active PvP.
- [x] Necromancer death -> deployed army loss.
- [x] Lost units become battlefield opportunities.
- [x] Spawn protection.
- [x] Combat logging/logout rules.
- [x] Kill attribution.
- [x] Anti-safe-zone abuse.
- [x] Threat/scouting UI.
- [x] Approximate enemy level/rebirth/army threat readability.

**Acceptance:**
- [x] Two players can fight, lose units, steal casualties and reverse
  momentum through raising.
- [x] Killing the Necromancer produces a meaningful but performant
  corpse/recovery event.
- [x] Death cannot be trivially exploited by logging/rejoining.

**2 October 2026 Phase 4 playtest evidence:**
- Roblox Studio's programmatic Server + Clients test connected two distinct
  simulated players (Player1 and Player2) and both client harnesses
  initialized successfully.
- Spawn protection blocked PvP damage until cleared; once protection ended,
  ordinary PvP damage became valid.
- Player2 lost one undead to Player1. The corpse assigned its Soul Claim to
  Player1, PvP unit-kill/loss counters updated, and Player1 successfully Raised
  it immediately. Player1's army increased from 3 -> 4 while Player2's fell
  from 3 -> 2, demonstrating battlefield momentum reversal through theft.
- The scouting HUD existed and became visible on both clients when the
  Necromancers were brought within scouting distance. It exposes approximate
  level, rebirth band and army-size threat rather than exact hidden strength.
- Moving a victim into the Sanctum/safe-zone bounds blocked PvP damage.
- PvP damage applied a combat tag and blocked retreat to the Sanctum while the
  tag remained active. The existing 10-second retreat channel also re-checks
  the tag at completion and cancels if the player moves.
- Killing Player2's Necromancer credited Player1 with the PvP kill, credited
  Player2 with the death, and converted Player2's two remaining deployed
  undead into claimed raisable corpses instead of deleting them.
- Player2 respawned with a fresh 3-unit starter army after the Necromancer
  death, while the previous army remained lost on the battlefield.
- A genuinely combat-tagged simulated client called LeaveTest() and
  disconnected. The server's PlayerRemoving path converted all three deployed
  units into COMBAT_LOGOUT corpses claimed for the opponent, preventing
  logging/rejoining from preserving the deployed army.
- Mass Necromancer-death validation at the full supported 300-unit army target
  dispatched the ownership-loss operation in about 8.4 ms and established all
  300 raisable claimed corpses in about 1.44 seconds in Studio.
- The same mass-death path at 100 units dispatched in about 1.8 ms and settled
  all 100 corpse resources in about 0.48 seconds.

## Phase 5 - Permanent collection, Masters and cloning

**Status:** COMPLETE - permanent collection, Masters, cloning, offline
production, upgrades and Master-risk acceptance GREEN on 2 October 2026.

**Goal:** create long-term ownership without removing battlefield risk.

Work:
- [x] DataStore-backed individual unit collection.
- [x] Master/Soul Imprint records.
- [x] Put unit into cloning chamber.
- [x] Remove Master from chamber and risk it.
- [x] Soul Essence/resource economy.
- [x] Clone timers.
- [x] Offline production.
- [x] Machine output caps.
- [x] Multiple machine support.
- [x] Base machine upgrades.
- [x] Exact preservation of template/size/trait/evolution/ability data.
- [x] Safe save/retry/versioning strategy.

**Acceptance:**
- [x] Extracted unit can become a permanent Master.
- [x] Player can leave and return without losing the Master.
- [x] Cloning progresses offline only while resource/storage rules allow it.
- [x] Player can deploy a clone and lose it without deleting the Master.
- [x] Player can deliberately remove and permanently risk the Master.

**2 October 2026 Phase 5 playtest evidence:**
- Added versioned individual unit records with unique IDs, exact template,
  size, trait, evolution, ability, provenance and command-cost data.
- Added the persistent Soul Vault and Master/Soul Imprint collection. Extracted
  units can be imprinted as Masters or dissolved into Soul Essence.
- Added a Soul Foundry UI in the Sanctum with Vault, Masters and Machines
  pages. The normal Backpack/army-manager UI continues to use the same
  persistent deployable-unit records.
- Starter-loan anti-farming was validated from a clean profile: five attempted
  starter extractions stored exactly three permanent starter units.
- A Giant Tough Skeleton Knight with the Stormcharged evolution and two
  abilities was imprinted, saved, reloaded and used as a cloning Master
  without losing any identity fields.
- Simulated offline elapsed time filled the level-1 machine to its exact 3/3
  output cap. Collecting produced exactly three clones, all retaining the
  Master's evolution, abilities and provenance.
- Soul Essence is consumed by production. Full output storage or insufficient
  resources pauses production instead of generating beyond allowed limits.
- Base level 2 created a second independent cloning machine. A level-2 machine
  upgrade and the second machine assignment both survived profile reload.
- Losing a deployed clone left its Master intact.
- Deliberately moving a Master out of Soul Imprint storage, deploying it and
  killing it removed that Master permanently.
- A different at-risk Master that survived deployment was extracted and
  correctly returned to safe Master storage with its evolution/ability data.
- The save layer uses a versioned DataStore profile, UpdateAsync revision
  checks and retry/backoff. When cloud DataStore access is unavailable in
  Studio, the same schema uses a session fallback so save/load and offline
  catch-up behaviour can still be exercised without mutating live data.
- A final clean runtime with all test harnesses removed loaded the Soul
  Collection, Backpack, formation, PvP and teleport systems without runtime
  errors. The Soul Foundry UI appeared in the Sanctum alongside the existing
  teleport and backpack UI.

## Phase 6 - Necromancer levels, capacity, skills and Rebirth

**Status:** COMPLETE - progression, skills, Rebirth and two-client PvP
acceptance GREEN on 2 October 2026.

**Goal:** create clear long-term progression without making veteran PvP
automatically unbeatable.

Work:
- [x] Persistent Necromancer XP and levels.
- [x] Command Capacity progression.
- [x] Raise proficiency progression.
- [x] Raise speed/reach progression.
- [x] Weighted unit capacity.
- [x] Skill-slot unlocks.
- [x] Maximum 3 equipped Necromancer skills.
- [x] Skill loadout changed only at Base.
- [x] Bone Wall, Fear Pulse, Rally, Corpse Explosion, Regroup,
  Sacrifice and Rebirth-only Frenzy.
- [x] Rebirth system.
- [x] Rebirth rewards focused on options/prestige/base progression rather
  than large raw combat multipliers.

**Acceptance:**
- [x] Level progression visibly expands army possibilities.
- [x] Level 1 works with a small army and no active skill slots.
- [x] Higher levels allow larger/more specialised compositions.
- [x] Rebirth adds meaningful options without applying veteran-only raw
  unit-stat multipliers.

**2 October 2026 Phase 6 playtest evidence:**
- Progression is stored inside the versioned Soul profile and survives the
  existing save/reload path.
- Level 1 starts at 5 Command Capacity, zero active skill slots, no Raise
  reach bonus and the original Raise channel duration.
- Weighted capacity was validated at level 1. A Giant Skeleton Knight plus
  a normal Skeleton Knight filled the full 5 Command Capacity; a further
  Skeleton was rejected. A 10-cost Grave Baron was also correctly blocked.
- Raise successes, NPC unit kills and enemy Necromancer kills award
  progression XP. The integrated test advanced level 1 to level 2 and
  retained the expected XP remainder.
- Level 30 provides 45 Command Capacity, three active skill slots, +5 studs
  of Raise reach and a 0.8 Raise channel multiplier.
- Level 30 successfully commanded four 10-cost Grave Barons while respecting
  the 45-point weighted capacity ceiling.
- Base-only loadout editing accepted a three-skill loadout and rejected the
  same edit attempt from the Arena.
- Bone Wall spawned five temporary blocking segments and respected cooldown.
- Rally applied the intended temporary army damage multiplier.
- Corpse Explosion consumed the selected corpse and dealt 34 damage in the
  acceptance test.
- Regroup returned displaced undead to the Necromancer, Fear Pulse disabled
  a nearby enemy temporarily, and Sacrifice traded one undead for player
  healing.
- Rebirth at level 30 reset level/XP/skill slots, incremented Rebirth and
  Prestige Mark counts, and persisted across a save/reload. Rebirth level 1
  had 7 Command Capacity rather than a raw damage advantage.
- Rebirth 1 unlocked Frenzy at level 10. Frenzy traded army health for a
  temporary damage option, preserving its risk/reward role.
- A real local-server test with two Studio clients passed. The level-1 player
  had 5 Command / 0 skill slots; the level-30 player had 45 Command /
  3 skill slots. Equivalent Skeletons had identical raw combat stats, both
  sides dealt PvP damage, and the smaller level-1 army still damaged the
  progressed player's larger army.
- Final production-runtime regression had all Phase 6 harnesses removed and
  restored the normal Teleport UI. Progression, Backpack and Teleport GUIs
  all loaded at level 1 with 5 Command / 0 skill slots and no runtime errors.

## Phase 7 - Factions and army identity

**Status:** COMPLETE - faction warfare, role identity and two-client
composition acceptance GREEN on 2 October 2026.

**Goal:** turn PvE into a source of strategically different army
components.

Work:
- [x] Multiple autonomous factions.
- [x] Faction-vs-faction conflicts.
- [x] Distinct shields, spears, archers, cavalry, casters, brutes,
  support, skirmishers and reavers.
- [x] Region/faction spawn identities.
- [x] Unit readability at distance.
- [x] Raised undead retain faction and combat role.
- [x] Faction-specific uncommon, elite and rare units.

**Acceptance:**
- [x] Two players at the same capacity can deliberately build visibly
  different armies.
- [x] Autonomous faction battles visibly demonstrate faction warfare.

**2 October 2026 Phase 7 playtest evidence:**
- Four regional factions now spawn from faction-specific rosters:
  Ossuary Legion, Mirebound Brood, Ashen Covenant and Grave Court.
- Natural runtime sampling produced all core combat roles, plus uncommon,
  elite and rare faction units with faction/role visual markers.
- Hostile factions now seek and fight each other rather than treating all
  wild NPC groups as interchangeable prey.
- A natural faction-war run confirmed hostile factions independently seek
  and fight one another without player initiation.
- The Phase 8 anti-farming rule supersedes the earlier faction-corpse rule:
  any unit killed by an NPC or faction NPC now vanishes and cannot be
  Raised by a player.
- Faction and role identity still persist when a player earns the kill and
  successfully Raises the defeated unit.
- Support units healed damaged faction allies during the live AI test.
- Cavalry and Reaver elite identities were spawned and retained their
  dedicated role visuals and combat attributes.
- A real local-server test with two Studio clients passed at equal
  12-point Command Capacity. One player used 8 units across
  Shield/Archer/Support; the other used 6 units across
  Brute/Cavalry/Skirmisher. Both armies used exactly 12 Command and all
  units retained visible faction identity.

## Phase 8 - Boss ownership and elite encounters

**Status:** COMPLETE - shared boss abilities, ownership rules and boss
capture acceptance GREEN on 2 October 2026.

**Goal:** make bosses aspirational army prizes, not only loot sources.

Work:
- [x] Boss ability framework shared between enemy and owned state.
- [x] Boss Raise difficulty.
- [x] Boss corpse presentation.
- [x] Boss cloning cost/time.
- [x] One-major-boss deployment restriction.
- [x] Boss command/AI behaviour within formations.
- [x] Boss-specific VFX/readability.

**Acceptance:**
- [x] Defeating and successfully raising a boss produces an owned boss
  with recognisably the same signature abilities.
- [x] Owned bosses are powerful but do not invalidate army composition.

**2 October 2026 Phase 8 playtest evidence:**
- Grave Baron now uses Soul Nova in both enemy and Raised-owned states.
- Crypt Warden now uses Grave Chain with damage and a temporary slow.
- Boss corpses receive a dedicated aura/light, a Major Boss Raise prompt
  and a 30-second decision window.
- Boss Raise chance is deliberately difficult: the normal 25% base chance
  can improve through progression but is capped at 45%.
- Boss cloning costs three times normal essence and takes three times the
  normal base machine time before machine-speed modifiers.
- Only one major boss can be deployed per player. Normal army units still
  deploy normally alongside that boss and retain weighted Command Capacity.
- Raised bosses retain their signature ability and Personal Guard cohort.
- NPC and faction-NPC kills of any unit destroy the victim immediately.
  They never create a player-raiseable corpse, preventing passive farming.
- The deterministic Studio acceptance passed enemy abilities, boss corpse
  presentation, boss Raise, owned abilities, the one-boss limit and normal
  composition in the same production runtime.
- A fresh canonical-place playtest loaded the full game runtime and UI with
  the Phase 8 services active and no runtime errors.

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

**Begin Phase 9: Events and undead evolution.**

Phase 8 now makes major bosses meaningful capture targets without letting
boss ownership replace normal army composition. Phase 9 should create
high-risk opportunities to transform already valuable undead.

The first Phase 9 slice is:
1. Define the reusable event framework and event lifecycle.
2. Build the first lightning/storm event with clear world telegraphing.
3. Define which owned undead are eligible for transformation.
4. Add explicit survival and failure risk during transformation.
5. Preserve transformed identity through Master and clone persistence.
6. Make event entry, danger, success and extraction readable to the player.
7. Validate a full valued-unit transformation and extraction loop.
