# Skill Issue Production Art Structure

This folder is the staging area for final visual assets. Keep generated assets here first; we will wire them into scenes after the folders are filled.

## Global Rules

- Format: PNG for sprites, UI, props, backgrounds. Keep transparent background for characters, props, effects, projectiles, chests, altars, and tiles.
- Direction: draw characters facing right. Godot can flip them horizontally.
- Pivot: character and enemy feet should be centered at the bottom of the frame.
- Scale: keep a consistent pixel-art scale across all assets. Avoid mixing sharp pixel art with soft painted sprites.
- Frame layout: use horizontal spritesheets unless noted otherwise. Every frame in one sheet must have the same size.
- File names: lowercase snake_case only, for example `player_run.png`, `boss_attack_slam.png`.
- Source files: put editable sources into each `source` folder, for example `.aseprite`, `.psd`, `.kra`, `.blend`.
- Do not overwrite `res://assets/generated_menu` unless the asset is specifically for the menu system.

## Optional Model Sources

Folder: `models`

Use this only if a character, enemy, or boss is generated as a 3D model first and then rendered into 2D sprites.

- `models/characters/player`: player model sources.
- `models/characters/enemies`: regular enemy model sources.
- `models/bosses`: boss model sources.
- Preferred source formats: `.blend`, `.fbx`, `.glb`, `.obj`.
- Final game-ready output should still be exported as PNG spritesheets into the matching `spritesheets` folder.

## Recommended Frame Sizes

- Player: 96x96 per frame.
- Regular enemies: 96x96 per frame.
- Bosses: 192x192 or 256x256 per frame, depending on silhouette.
- Chest / altar / exit props: 128x128 per frame.
- Small effects and projectiles: 64x64 per frame.
- Tiles: 64x64 base tiles. Platform strips can be 64x16 or 64x32.
- Level backgrounds: 1920x1080.
- Parallax layers: 1920x1080 each, transparent where needed.
- Menu card images: 1024x1024 source is fine; final UI crops them into frames.

## Player Required Assets

Folder: `characters/player`

- `spritesheets/player_idle.png`: idle loop.
- `spritesheets/player_run.png`: running loop.
- `spritesheets/player_jump.png`: jump start / rise.
- `spritesheets/player_fall.png`: falling.
- `spritesheets/player_land.png`: landing impact.
- `spritesheets/player_hurt.png`: damage reaction.
- `spritesheets/player_death.png`: defeat animation.
- `spritesheets/player_parry_shield.png`: shield/parry pose.
- `spritesheets/player_melee_combo_01.png`: first melee hit.
- `spritesheets/player_melee_combo_02.png`: second melee hit.
- `spritesheets/player_melee_combo_03.png`: third melee finisher.
- `spritesheets/player_ranged_combo_01.png`: first ranged shot.
- `spritesheets/player_ranged_combo_02.png`: double shot.
- `spritesheets/player_ranged_combo_03.png`: triple shot.
- `weapons/player_sword.png`: sword overlay if separated from the body.
- `weapons/player_shield.png`: shield overlay.
- `weapons/player_projectile.png`: player shot projectile.
- `portraits/player_dialogue.png`: dialogue portrait.

## Regular Enemy Required Assets

Folder: `characters/enemies`

### Melee Sentinel

- `melee_sentinel/spritesheets/melee_idle.png`
- `melee_sentinel/spritesheets/melee_patrol.png`
- `melee_sentinel/spritesheets/melee_telegraph.png`
- `melee_sentinel/spritesheets/melee_attack.png`
- `melee_sentinel/spritesheets/melee_hurt.png`
- `melee_sentinel/spritesheets/melee_death.png`
- `melee_sentinel/spritesheets/melee_parried.png`

### Ranged Sentinel

- `ranged_sentinel/spritesheets/ranged_idle.png`
- `ranged_sentinel/spritesheets/ranged_patrol.png`
- `ranged_sentinel/spritesheets/ranged_telegraph.png`
- `ranged_sentinel/spritesheets/ranged_shoot.png`
- `ranged_sentinel/spritesheets/ranged_jump_back.png`
- `ranged_sentinel/spritesheets/ranged_hurt.png`
- `ranged_sentinel/spritesheets/ranged_death.png`
- `ranged_sentinel/spritesheets/ranged_parried.png`
- `shared_projectiles/enemy_projectile.png`
- `shared_projectiles/reflected_projectile.png`

## Boss Required Assets

Folder: `bosses`

Each boss folder has the same internal structure: `spritesheets`, `portraits`, `projectiles`, `arena_props`, `source`.

### Boss 1: Threshold Warden

Theme: variables. Mechanic: pressure threshold / reprogramming.

- `bosses/01_threshold_warden/spritesheets/idle.png`
- `bosses/01_threshold_warden/spritesheets/move.png`
- `bosses/01_threshold_warden/spritesheets/telegraph.png`
- `bosses/01_threshold_warden/spritesheets/attack_threshold.png`
- `bosses/01_threshold_warden/spritesheets/hurt.png`
- `bosses/01_threshold_warden/spritesheets/death.png`
- `bosses/01_threshold_warden/portraits/dialogue.png`

### Boss 2: Logic Spider

Theme: if / else. Mechanic: branching patterns.

- `bosses/02_logic_spider/spritesheets/idle.png`
- `bosses/02_logic_spider/spritesheets/crawl.png`
- `bosses/02_logic_spider/spritesheets/telegraph_branch.png`
- `bosses/02_logic_spider/spritesheets/attack_branch.png`
- `bosses/02_logic_spider/spritesheets/hurt.png`
- `bosses/02_logic_spider/spritesheets/death.png`
- `bosses/02_logic_spider/portraits/dialogue.png`

### Boss 3: Assembly Golem

Theme: loops. Mechanic: repeated attack cycles.

- `bosses/03_assembly_golem/spritesheets/idle.png`
- `bosses/03_assembly_golem/spritesheets/walk.png`
- `bosses/03_assembly_golem/spritesheets/telegraph_loop.png`
- `bosses/03_assembly_golem/spritesheets/attack_loop.png`
- `bosses/03_assembly_golem/spritesheets/hurt.png`
- `bosses/03_assembly_golem/spritesheets/death.png`
- `bosses/03_assembly_golem/portraits/dialogue.png`

### Boss 4: Archivist

Theme: functions. Mechanic: named reusable patterns.

- `bosses/04_archivist/spritesheets/idle.png`
- `bosses/04_archivist/spritesheets/float.png`
- `bosses/04_archivist/spritesheets/telegraph_function.png`
- `bosses/04_archivist/spritesheets/attack_function.png`
- `bosses/04_archivist/spritesheets/hurt.png`
- `bosses/04_archivist/spritesheets/death.png`
- `bosses/04_archivist/portraits/dialogue.png`

### Boss 5: System Admin

Theme: integration. Mechanic: combined systems.

- `bosses/05_system_admin/spritesheets/idle.png`
- `bosses/05_system_admin/spritesheets/move.png`
- `bosses/05_system_admin/spritesheets/telegraph_system.png`
- `bosses/05_system_admin/spritesheets/attack_system.png`
- `bosses/05_system_admin/spritesheets/teleport_dissolve.png`
- `bosses/05_system_admin/spritesheets/teleport_materialize.png`
- `bosses/05_system_admin/spritesheets/hurt.png`
- `bosses/05_system_admin/spritesheets/death.png`
- `bosses/05_system_admin/portraits/dialogue.png`

## Interactables Required Assets

Folder: `interactables`

- `chests/spritesheets/chest_idle.png`
- `chests/spritesheets/chest_open.png`
- `chests/spritesheets/chest_locked.png`
- `chests/icons/chest_hint_icon.png`
- `altars/spritesheets/altar_idle.png`
- `altars/spritesheets/altar_activate.png`
- `altars/spritesheets/altar_complete.png`
- `exits/spritesheets/exit_locked.png`
- `exits/spritesheets/exit_open.png`

## Level Art Required Assets

Folder: `levels`

Each level folder has `backgrounds`, `parallax`, `tilesets`, `platforms`, `props`, `hazards`, and `source`.

- `tutorial`: training room visuals, arrow-friendly props, simple floor/platform set.
- `level_01_variables`: archive/variable chamber style.
- `level_02_if_else`: branching paths, signs, switches, forked architecture.
- `level_03_loops`: repeating machinery, conveyor/platform rhythm.
- `level_04_functions`: library/lab modules, reusable symbol props.
- `level_05_integration`: system core, mixed environments, final synthesis.

For each level:

- `backgrounds/background.png`: full background.
- `parallax/layer_01_sky.png`
- `parallax/layer_02_far.png`
- `parallax/layer_03_mid.png`
- `parallax/layer_04_front.png`
- `tilesets/tileset_ground.png`
- `tilesets/tileset_walls.png`
- `platforms/platform_one_way.png`
- `props/props_common.png`
- `hazards/hazards.png`

## Boss Arena Required Assets

Folder: `boss_arenas`

Each arena should match its boss mechanic:

- `boss_01_threshold_warden`: variable locks, pressure gates, threshold pillars.
- `boss_02_logic_spider`: branching platforms, if/else gates, forked paths.
- `boss_03_assembly_golem`: loop machinery, repeating pistons, cyclic platforms.
- `boss_04_archivist`: floating books, function sigils, modular archives.
- `boss_05_system_admin`: system core, glitch panels, teleport indicators.

Required per arena:

- `background.png`
- `floor.png`
- `platforms.png`
- `foreground_props.png`
- `hazard_props.png`
- `teleport_indicator.png` if the boss uses teleporting.

## Effects Required Assets

Folder: `effects`

- `combat/hit_spark.png`
- `combat/slash_arc.png`
- `combat/parry_flash.png`
- `combat/shield_reflect.png`
- `combat/death_burst.png`
- `projectiles/player_shot_trail.png`
- `projectiles/enemy_shot_trail.png`
- `boss/teleport_indicator.png`
- `boss/dissolve_particles.png`
- `terminal/task_success_flash.png`
- `terminal/task_error_flash.png`
- `pickup/chest_reward.png`
- `pickup/altar_energy.png`

## UI Required Assets

Folder: `ui`

Use this only for future UI pieces that are not already in `generated_menu`.

- `hud/health_bar_frame.png`
- `hud/health_bar_fill.png`
- `hud/boss_bar_frame.png`
- `hud/boss_bar_fill.png`
- `terminal/terminal_panel.png`
- `terminal/code_editor_frame.png`
- `dialogue/dialogue_box.png`
- `dialogue/nameplate.png`
- `inventory/hint_slot.png`

## Animation Manifest

When you generate a spritesheet, add a small `.json` next to it if the frame timing is not obvious.

Example:

```json
{
  "frame_size": [96, 96],
  "fps": 12,
  "loop": true,
  "frames": 8,
  "pivot": "bottom_center"
}
```
