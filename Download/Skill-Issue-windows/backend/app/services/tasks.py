from __future__ import annotations

import json
import random
from datetime import datetime, timezone
from threading import RLock

from app.models import Difficulty, LevelTheme, TaskGenerationRequest, TaskGenerationResponse
from app.services.llm import generate_llm_task_with_detail
from app.services.logger import LOG_DIRECTORY, summarize_user_theme_attempts

RNG = random.SystemRandom()
TASK_STACK_FILE_PATH = LOG_DIRECTORY / "generated_task_stack.json"
TASK_HISTORY_FILE_PATH = LOG_DIRECTORY / "generated_tasks.jsonl"
TASK_STACK_TARGET_SIZE = 2
TASK_STACK_MAX_PER_KEY = 5
_TASK_STACK_LOCK = RLock()
_TASK_STACK_FAILURES: dict[str, str] = {}

CONCEPT_ALIASES: dict[str, list[str]] = {
    "weapon": ["weapon", "blade", "sword", "forge", "forged weapon"],
    "weapon_mode": ["weapon mode", "attack mode", "combat mode", "blade mode"],
    "weapon_range": ["weapon range", "reach", "attack range", "strike reach"],
    "weapon_weight": ["weapon weight", "blade weight", "weapon balance", "balance"],
    "damage": ["damage", "attack damage", "attack power", "strike power", "hit power"],
    "ranged_damage": ["ranged damage", "shot damage", "projectile damage", "volley damage"],
    "melee_damage": ["melee damage", "blade damage", "slash damage", "sword damage"],
    "speed": ["speed", "movement speed", "move speed", "dash speed", "mobility"],
    "guard_window": ["guard window", "parry window", "block timing", "deflect timing"],
    "recovery": ["recovery", "recovery timing", "cooldown recovery", "reset timing"],
    "hp": ["hp", "health", "integrity", "vitality", "health pool"],
    "shield": ["shield", "barrier", "shield durability", "barrier strength", "defense layer"],
    "armor": ["armor", "protection", "durability", "defense"],
    "stamina": ["stamina", "energy", "combat energy", "energy reserve"],
    "stamina_regen": ["stamina regen", "energy recovery", "stamina recovery", "regen"],
    "projectile_speed": ["projectile speed", "shot speed", "bolt speed", "volley speed"],
    "attack_delay": ["attack delay", "attack timing", "attack cooldown", "strike delay"],
    "dash_speed": ["dash speed", "burst speed", "rush speed"],
    "jump_height": ["jump height", "air height", "jump reach"],
    "crit_damage": ["critical damage", "crit damage", "critical hit power"],
    "crit_window": ["critical window", "crit window", "critical timing"],
}

BASES: dict[LevelTheme, dict[str, object]] = {
    "variables": {"title": "Variables", "body": "Variables store gameplay values such as damage, hp, shield, or timing.", "rules": ["Use assignments only.", "Keep one concept per line.", "Name stats clearly."]},
    "conditions": {"title": "If / Else", "body": "Conditions connect a combat state to the right action instead of guessing.", "rules": ["Use a readable branch.", "Tie one state to one action.", "Keep the branch short."]},
    "loops": {"title": "Loops", "body": "Loops repeat one useful action with a clear stopping rule.", "rules": ["Repeat one compact step.", "Show the stop rule clearly.", "Keep the loop body short."]},
    "functions": {"title": "Functions", "body": "Functions package a tactic into one reusable helper and then call it.", "rules": ["Define before calling.", "Keep the helper focused.", "Reuse the helper instead of copying lines."]},
    "integration": {"title": "Integration", "body": "Integration mixes earlier tools into one compact tactic.", "rules": ["Use at least two constructs.", "Keep the whole snippet readable.", "Make each part support the same tactic."]},
}

SPECS: dict[LevelTheme, list[dict[str, object]]] = {
    "variables": [
        {"t": "Damage Calibration", "p": "Assign values for damage and speed so the knight reaches the enemy before the next exchange.", "k": ["damage", "speed"], "v": ["damage", "speed"], "e": "damage = 12\nspeed = 4"},
        {"t": "Shield Buffer", "p": "Set hp and shield variables so the knight survives the next ranged volley.", "k": ["hp", "shield"], "v": ["hp", "shield"], "e": "hp = 120\nshield = 8"},
        {"t": "Parry Timing", "p": "Assign values for guard_window and recovery so parries stay available during the next clash.", "k": ["guard_window", "recovery"], "v": ["guard_window", "recovery"], "e": "guard_window = 2\nrecovery = 1"},
        {"t": "Rush Setup", "p": "Tune dash_speed and attack_delay to create a faster opening strike.", "k": ["dash_speed", "attack_delay"], "v": ["dash_speed", "attack_delay"], "e": "dash_speed = 7\nattack_delay = 1"},
        {"t": "Durability Pass", "p": "Assign armor and hp_regen values to stabilize the next combat window.", "k": ["armor", "hp_regen"], "v": ["armor", "hp_regen"], "e": "armor = 5\nhp_regen = 2"},
        {"t": "Critical Window", "p": "Set crit_damage and crit_window so the next punish hits harder.", "k": ["crit_damage", "crit_window"], "v": ["crit_damage", "crit_window"], "e": "crit_damage = 18\ncrit_window = 2"},
        {"t": "Mobility Tune", "p": "Assign dodge_speed and jump_height values to improve movement through the next arena step.", "k": ["dodge_speed", "jump_height"], "v": ["dodge_speed", "jump_height"], "e": "dodge_speed = 6\njump_height = 3"},
        {"t": "Energy Reserve", "p": "Store stamina and stamina_regen values so the knight can keep attacking safely.", "k": ["stamina", "stamina_regen"], "v": ["stamina", "stamina_regen"], "e": "stamina = 10\nstamina_regen = 3"},
        {"t": "Volley Prep", "p": "Assign projectile_speed and ranged_damage to strengthen the next ranged burst.", "k": ["projectile_speed", "ranged_damage"], "v": ["projectile_speed", "ranged_damage"], "e": "projectile_speed = 9\nranged_damage = 14"},
        {"t": "Precision Overclock", "p": "Assign values for damage, speed, and guard_window to optimize a risky attack pattern.", "k": ["damage", "speed", "guard_window"], "v": ["damage", "speed", "guard_window"], "e": "damage = 16\nspeed = 5\nguard_window = 1"},
    ],
    "conditions": [
        {"t": "Distance Branch", "p": "Use if/else to choose melee when the enemy is close and ranged pressure otherwise.", "k": ["if", "else", "enemy_distance", "melee", "ranged"], "v": ["enemy_distance", "melee", "ranged"], "e": "if enemy_distance < 40:\n    action = 'melee'\nelse:\n    action = 'ranged'"},
        {"t": "Guard Check", "p": "Choose between guard and strike with one if/else branch based on incoming damage.", "k": ["if", "else", "incoming_damage", "guard", "strike"], "v": ["incoming_damage", "guard", "strike"], "e": "if incoming_damage > 10:\n    action = 'guard'\nelse:\n    action = 'strike'"},
        {"t": "Low HP Decision", "p": "Write a branch that heals when hp is low and attacks otherwise.", "k": ["if", "else", "hp", "heal", "attack"], "v": ["hp", "heal", "attack"], "e": "if hp < 40:\n    action = 'heal'\nelse:\n    action = 'attack'"},
        {"t": "Parry Read", "p": "Use a condition to parry when the enemy is winding up and dash otherwise.", "k": ["if", "enemy_winding_up", "parry", "dash"], "v": ["enemy_winding_up", "parry", "dash"], "e": "if enemy_winding_up:\n    action = 'parry'\nelse:\n    action = 'dash'"},
        {"t": "Safe Shot", "p": "Pick ranged fire only when the lane is clear, otherwise reposition.", "k": ["if", "lane_clear", "ranged", "reposition"], "v": ["lane_clear", "ranged", "reposition"], "e": "if lane_clear:\n    action = 'ranged'\nelse:\n    action = 'reposition'"},
        {"t": "Pressure Branch", "p": "Choose punish or retreat depending on whether the boss shield is open.", "k": ["if", "boss_shield_open", "punish", "retreat"], "v": ["boss_shield_open", "punish", "retreat"], "e": "if boss_shield_open:\n    action = 'punish'\nelse:\n    action = 'retreat'"},
        {"t": "Range Safety", "p": "Write one if/else check that blocks when the enemy is too close and shoots otherwise.", "k": ["if", "enemy_distance", "block", "shoot"], "v": ["enemy_distance", "block", "shoot"], "e": "if enemy_distance < 20:\n    action = 'block'\nelse:\n    action = 'shoot'"},
        {"t": "Burst Gate", "p": "Use one condition to burst when energy is high and recharge otherwise.", "k": ["if", "energy", "burst", "recharge"], "v": ["energy", "burst", "recharge"], "e": "if energy > 7:\n    action = 'burst'\nelse:\n    action = 'recharge'"},
        {"t": "Aggro Split", "p": "Choose dash or parry with a readable branch based on boss state.", "k": ["if", "boss_state", "dash", "parry"], "v": ["boss_state", "dash", "parry"], "e": "if boss_state == 'open':\n    action = 'dash'\nelse:\n    action = 'parry'"},
        {"t": "Risk Filter", "p": "Use if/else logic to attack only when the arena state is safe and guard otherwise.", "k": ["if", "else", "arena_safe", "attack", "guard"], "v": ["arena_safe", "attack", "guard"], "e": "if arena_safe:\n    action = 'attack'\nelse:\n    action = 'guard'"},
    ],
    "loops": [
        {"t": "Triple Volley", "p": "Write a loop that repeats a ranged action three times.", "k": ["loop", "repeat", "ranged", "three"], "v": ["range", "shoot"], "e": "for _ in range(3):\n    shoot()"},
        {"t": "Shield Pulse", "p": "Use a loop to apply a shield action four times before the next wave.", "k": ["loop", "shield", "four"], "v": ["range", "shield"], "e": "for _ in range(4):\n    raise_shield()"},
        {"t": "Damage Cycle", "p": "Repeat one damage boost several times with a clear stopping rule.", "k": ["loop", "damage", "stopping rule"], "v": ["range", "damage"], "e": "for _ in range(3):\n    boost_damage()"},
        {"t": "Dash Rhythm", "p": "Build a short loop that repeats a dash step during the next phase.", "k": ["loop", "dash", "repeat"], "v": ["range", "dash"], "e": "for _ in range(2):\n    dash()"},
        {"t": "Recovery Loop", "p": "Use a loop to repeat a small heal or recovery action with control.", "k": ["loop", "heal", "recovery"], "v": ["loop", "recover"], "e": "for _ in range(3):\n    recover()"},
        {"t": "Pressure Chain", "p": "Write one loop that keeps pressure on the enemy for several short actions.", "k": ["loop", "pressure", "actions"], "v": ["loop", "attack"], "e": "for _ in range(3):\n    attack()"},
        {"t": "Guard Sequence", "p": "Repeat a guard action in a controlled loop for the next defensive window.", "k": ["loop", "guard", "controlled"], "v": ["loop", "guard"], "e": "for _ in range(3):\n    guard()"},
        {"t": "Burst Pattern", "p": "Create a loop that alternates repeated pressure through a short burst cycle.", "k": ["loop", "burst", "cycle"], "v": ["loop", "burst"], "e": "for _ in range(2):\n    burst()"},
        {"t": "Stamina Drill", "p": "Use a loop to restore stamina in repeated steps before the next exchange.", "k": ["loop", "stamina", "steps"], "v": ["loop", "stamina"], "e": "for _ in range(4):\n    restore_stamina()"},
        {"t": "Cycle Pattern", "p": "Build a short loop that keeps a repeated combat pattern under control.", "k": ["loop", "pattern", "control"], "v": ["loop", "pattern"], "e": "for _ in range(5):\n    attack()"},
    ],
    "functions": [
        {"t": "Combo Helper", "p": "Define one function for a combo step and call it once.", "k": ["def", "function", "call", "combo"], "v": ["def", "call", "combo"], "e": "def combo_step():\n    attack()\n\ncombo_step()"},
        {"t": "Shield Helper", "p": "Create one helper function that raises a shield and then call it.", "k": ["def", "helper", "shield", "call"], "v": ["def", "shield", "call"], "e": "def raise_barrier():\n    shield = 1\n\nraise_barrier()"},
        {"t": "Heal Routine", "p": "Write a function that handles a small heal step and use it once.", "k": ["def", "heal", "function", "call"], "v": ["def", "heal", "call"], "e": "def small_heal():\n    hp = 100\n\nsmall_heal()"},
        {"t": "Punish Helper", "p": "Define a punish function for the next opening and call it in the tactic.", "k": ["def", "punish", "call"], "v": ["def", "punish", "call"], "e": "def punish_window():\n    attack()\n\npunish_window()"},
        {"t": "Range Utility", "p": "Create a reusable ranged helper and call it once.", "k": ["def", "ranged", "helper", "call"], "v": ["def", "ranged", "call"], "e": "def ranged_press():\n    shoot()\n\nranged_press()"},
        {"t": "Forge Helper", "p": "Write one helper function that tunes a weapon stat and then call it.", "k": ["def", "helper", "weapon", "call"], "v": ["def", "weapon", "call"], "e": "def tune_weapon():\n    damage = 15\n\ntune_weapon()"},
        {"t": "Recovery Function", "p": "Define a function for recovery timing and use it once.", "k": ["def", "recovery", "function", "call"], "v": ["def", "recovery", "call"], "e": "def recovery_step():\n    recover()\n\nrecovery_step()"},
        {"t": "Dash Utility", "p": "Create a small function that handles a dash response and call it.", "k": ["def", "dash", "function", "call"], "v": ["def", "dash", "call"], "e": "def dash_out():\n    dash()\n\ndash_out()"},
        {"t": "Energy Helper", "p": "Write a helper function that spends or restores energy and call it once.", "k": ["def", "energy", "helper", "call"], "v": ["def", "energy", "call"], "e": "def manage_energy():\n    energy = 5\n\nmanage_energy()"},
        {"t": "Boss Utility", "p": "Define a compact helper for defense or punish timing and call it in the main tactic.", "k": ["def", "defense", "punish", "call"], "v": ["def", "defense", "call"], "e": "def guard_window():\n    guard()\n\nguard_window()"},
    ],
    "integration": [
        {"t": "Mixed Tactic", "p": "Combine variables with a condition to improve the knight's next combat decision.", "k": ["variables", "condition", "decision"], "v": ["assignment", "if"], "e": "damage = 12\nif enemy_close:\n    attack()"},
        {"t": "Hybrid Pressure", "p": "Mix a stat setup with a short loop to create a stronger pressure pattern.", "k": ["variables", "loop", "pressure"], "v": ["assignment", "loop"], "e": "damage = 12\nfor _ in range(2):\n    attack()"},
        {"t": "Helper Branch", "p": "Use a function and a condition together to control the next tactic.", "k": ["function", "condition", "tactic"], "v": ["def", "if"], "e": "def strike():\n    attack()\n\nif enemy_close:\n    strike()"},
        {"t": "Defensive Mix", "p": "Combine hp setup and one branch to survive the next exchange.", "k": ["hp", "if", "survive"], "v": ["assignment", "if"], "e": "hp = 120\nif incoming_damage > 10:\n    guard()"},
        {"t": "Volley Routine", "p": "Mix a ranged stat with a loop or function to create a compact volley tactic.", "k": ["ranged", "loop", "function"], "v": ["assignment", "loop"], "e": "ranged_damage = 14\nfor _ in range(2):\n    shoot()"},
        {"t": "Adaptive Routine", "p": "Build a routine that uses variables and branching to react to the enemy.", "k": ["variables", "branching", "enemy"], "v": ["assignment", "if"], "e": "speed = 5\nif enemy_distance < 30:\n    dash()"},
        {"t": "Stamina Pattern", "p": "Combine stamina setup with a repeat or helper pattern to hold pressure safely.", "k": ["stamina", "repeat", "helper"], "v": ["assignment", "loop"], "e": "stamina = 8\nfor _ in range(2):\n    attack()"},
        {"t": "Forge System", "p": "Use two different programming ideas together to tune a forged weapon tactic.", "k": ["two ideas", "weapon", "tactic"], "v": ["assignment", "def"], "e": "weapon_damage = 15\ndef forge_step():\n    attack()"},
        {"t": "Reaction Stack", "p": "Combine a branch with a helper or loop so the knight reacts with more control.", "k": ["branch", "helper", "loop", "react"], "v": ["if", "def"], "e": "def recover():\n    guard()\n\nif hp < 40:\n    recover()"},
        {"t": "System Sync", "p": "Build a compact multi-part tactic using several tools from earlier levels.", "k": ["multi-part", "tactic", "tools"], "v": ["assignment", "if", "loop"], "e": "damage = 16\nif enemy_close:\n    for _ in range(2):\n        attack()"},
    ],
}

BOSS_FLAVORS: dict[LevelTheme, list[str]] = {
    "variables": ["Threshold Phase", "Shield Gate", "Burst Window", "Core Rebalance", "Overload Prep", "Parry Reserve", "Pressure Sync", "Warden Offset", "Safety Buffer", "Final Tuning"],
    "conditions": ["Branch Read", "Spider Check", "Open Guard", "Decision Gate", "Phase Split", "Punish Filter", "Threat Branch", "Admin Choice", "Arena Switch", "Logic Break"],
    "loops": ["Cycle Break", "Pattern Ladder", "Golem Rhythm", "Pressure Loop", "Guard Cycle", "Volley Loop", "Arena Cycle", "Recovery Chain", "Sequence Hold", "Loop Lock"],
    "functions": ["Archive Helper", "Boss Utility", "Phase Helper", "Punish Routine", "Defense Helper", "Dash Routine", "Admin Helper", "Pattern Call", "Safe Routine", "Final Helper"],
    "integration": ["System Phase", "Mixed Counter", "Admin Sync", "Final Stack", "Hybrid Break", "Control Mesh", "Arena Sync", "Phase Fusion", "Counter System", "Integration Seal"],
}

ALTAR_FOCI: list[dict[str, object]] = [
    {"name": "Blade Edge", "a": "melee_damage", "b": "weapon_weight", "action": "slash", "example": "blade_power = 12\nblade_balance = 4"},
    {"name": "Ranged Rune", "a": "ranged_damage", "b": "projectile_speed", "action": "shoot", "example": "shot_power = 10\nbolt_speed = 7"},
    {"name": "Guard Sigil", "a": "guard_window", "b": "shield", "action": "guard", "example": "parry_time = 2\nbarrier_strength = 8"},
    {"name": "Swift Hilt", "a": "speed", "b": "attack_delay", "action": "strike", "example": "move_speed = 5\nstrike_delay = 1"},
    {"name": "Heavy Core", "a": "damage", "b": "armor", "action": "heavy_strike", "example": "attack_power = 15\narmor_value = 6"},
    {"name": "Vital Grip", "a": "hp", "b": "stamina", "action": "recover", "example": "health_pool = 120\nenergy_reserve = 9"},
    {"name": "Critical Groove", "a": "crit_damage", "b": "crit_window", "action": "punish", "example": "critical_power = 18\ncritical_timing = 2"},
    {"name": "Long Reach", "a": "weapon_range", "b": "damage", "action": "reach_strike", "example": "attack_range = 6\nstrike_power = 13"},
    {"name": "Balanced Form", "a": "weapon_mode", "b": "speed", "action": "switch_form", "example": "blade_mode = 'safe'\nmove_speed = 4"},
    {"name": "Recovery Seal", "a": "recovery", "b": "guard_window", "action": "reset_guard", "example": "reset_timing = 2\nparry_window = 3"},
]


def generate_task(payload: TaskGenerationRequest) -> TaskGenerationResponse:
    summary: dict[str, int | Difficulty] = summarize_user_theme_attempts(payload.user_id, payload.level_theme)
    difficulty: Difficulty = summary["suggested_difficulty"]  # type: ignore[assignment]
    adaptation_reason: str = _build_adaptation_reason(summary)
    if payload.generation_mode == "patterns":
        return _fallback_and_log(payload, difficulty, adaptation_reason, "Pattern mode selected in Settings")
    if not payload.llm_api_key.strip():
        return _fallback_and_log(payload, difficulty, adaptation_reason, "API key missing from Settings")
    prepared_task: TaskGenerationResponse | None = _pop_task_from_stack(payload, difficulty)
    if prepared_task is not None:
        _log_generated_task(payload, difficulty, prepared_task, "served_from_stack")
        return prepared_task
    return _fallback_and_log(payload, difficulty, adaptation_reason, _empty_stack_detail(payload, difficulty))


def prewarm_task_stack(payload: TaskGenerationRequest, target_size: int = TASK_STACK_TARGET_SIZE) -> None:
    if payload.generation_mode == "patterns" or not payload.llm_api_key.strip():
        return
    summary: dict[str, int | Difficulty] = summarize_user_theme_attempts(payload.user_id, payload.level_theme)
    difficulty: Difficulty = summary["suggested_difficulty"]  # type: ignore[assignment]
    adaptation_reason: str = _build_adaptation_reason(summary)
    for _index in range(max(1, target_size)):
        if _stack_count(payload, difficulty) >= target_size:
            return
        try:
            llm_task, llm_detail = generate_llm_task_with_detail(
                interaction_type=payload.interaction_type,
                level_theme=payload.level_theme,
                difficulty=difficulty,
                language=payload.language,
                encounter_name=payload.encounter_name,
                encounter_style=payload.encounter_style,
                gameplay_context=payload.gameplay_context,
                structure_focus=payload.structure_focus,
                boss_mechanic=payload.boss_mechanic,
                tutorial_mode=payload.tutorial_mode,
                adaptation_reason=adaptation_reason,
                llm_api_key=payload.llm_api_key,
            )
        except Exception as exc:
            _log_generation_failure(payload, difficulty, "prewarm exception: %s" % exc.__class__.__name__)
            return
        if llm_task is None:
            _log_generation_failure(payload, difficulty, llm_detail)
            return
        _push_task_to_stack(payload, difficulty, llm_task)
        _log_generated_task(payload, difficulty, llm_task, "prewarmed")


def _build_adaptation_reason(summary: dict[str, int | Difficulty]) -> str:
    successes: int = int(summary["successes"])
    failures: int = int(summary["failures"])
    streak: int = int(summary["current_streak"])
    if streak >= 3:
        return "The player solved several recent tasks in this theme, so the task can be more demanding."
    if streak <= -2:
        return "The player struggled in recent tasks in this theme, so the task should stay simpler and more direct."
    if successes > failures:
        return "The player is handling this theme reasonably well, so use a balanced challenge."
    return "The player still needs a stable foundation in this theme, so keep the task short and clear."


def _fallback_task(payload: TaskGenerationRequest, difficulty: Difficulty, adaptation_reason: str, generation_detail: str) -> TaskGenerationResponse:
    source_patterns: list[dict[str, object]] = _build_altar_patterns(payload.level_theme) if payload.interaction_type == "altar" else _build_patterns(payload.level_theme)
    pattern: dict[str, object] = RNG.choice(source_patterns).copy()
    if payload.interaction_type == "boss":
        pattern = _bossify(_build_boss_pattern(payload, pattern), payload)
    return TaskGenerationResponse(
        interaction_type=payload.interaction_type,
        level_theme=payload.level_theme,
        difficulty=difficulty,
        language=payload.language,
        generation_source="fallback",
        generation_detail=generation_detail,
        title=str(pattern["title"]),
        prompt=_context_prompt(str(pattern["prompt"]), payload),
        gameplay_effect=_context_effect(str(pattern["gameplay_effect"]), payload),
        syntax_rules=_norm(pattern["syntax_rules"]),
        explanation_title=str(pattern["explanation_title"]),
        explanation_body=_context_explanation(str(pattern["explanation_body"]), payload),
        explanation_rules=_norm(pattern["explanation_rules"]),
        explanation_prompt=_context_explanation_prompt(str(pattern["explanation_prompt"]), payload),
        keywords=_norm(pattern["keywords"]),
        example_code=_scale_example(str(pattern["example_code"]), difficulty),
        adaptation_reason=adaptation_reason,
        fallback_hints=_norm(pattern["fallback_hints"]),
        validation_targets=_norm(pattern["validation_targets"]),
        pattern_id=str(pattern["pattern_id"]),
    )


def _fallback_and_log(payload: TaskGenerationRequest, difficulty: Difficulty, adaptation_reason: str, generation_detail: str) -> TaskGenerationResponse:
    response = _fallback_task(payload, difficulty, adaptation_reason, generation_detail)
    _log_generated_task(payload, difficulty, response, "served_fallback")
    return response


def _pop_task_from_stack(payload: TaskGenerationRequest, difficulty: Difficulty) -> TaskGenerationResponse | None:
    stack_key = _task_stack_key(payload, difficulty)
    with _TASK_STACK_LOCK:
        stack = _read_stack_locked()
        queue = stack.get(stack_key, [])
        if not isinstance(queue, list) or not queue:
            return None
        entry = queue.pop(0)
        if queue:
            stack[stack_key] = queue
        else:
            stack.pop(stack_key, None)
        _write_stack_locked(stack)
    if not isinstance(entry, dict):
        return None
    task_data = entry.get("task", {})
    if not isinstance(task_data, dict):
        return None
    try:
        response = TaskGenerationResponse(**task_data)
    except Exception:
        return None
    response.generation_detail = "Pre-generated task stack"
    return response


def _push_task_to_stack(payload: TaskGenerationRequest, difficulty: Difficulty, task: TaskGenerationResponse) -> None:
    stack_key = _task_stack_key(payload, difficulty)
    entry = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "interaction_type": payload.interaction_type,
        "level_theme": payload.level_theme,
        "difficulty": difficulty,
        "task": task.model_dump(),
    }
    with _TASK_STACK_LOCK:
        stack = _read_stack_locked()
        queue = stack.get(stack_key, [])
        if not isinstance(queue, list):
            queue = []
        queue.append(entry)
        stack[stack_key] = queue[-TASK_STACK_MAX_PER_KEY:]
        _write_stack_locked(stack)


def _stack_count(payload: TaskGenerationRequest, difficulty: Difficulty) -> int:
    stack_key = _task_stack_key(payload, difficulty)
    with _TASK_STACK_LOCK:
        stack = _read_stack_locked()
        queue = stack.get(stack_key, [])
    return len(queue) if isinstance(queue, list) else 0


def _task_stack_key(payload: TaskGenerationRequest, difficulty: Difficulty) -> str:
    return json.dumps(
        {
            "interaction_type": payload.interaction_type,
            "level_theme": payload.level_theme,
            "difficulty": difficulty,
            "language": payload.language,
            "encounter_name": payload.encounter_name,
            "encounter_style": payload.encounter_style,
            "structure_focus": payload.structure_focus,
            "boss_mechanic": payload.boss_mechanic,
            "tutorial_mode": payload.tutorial_mode,
        },
        ensure_ascii=True,
        sort_keys=True,
    )


def _read_stack_locked() -> dict[str, list[dict]]:
    if not TASK_STACK_FILE_PATH.exists():
        return {}
    try:
        parsed = json.loads(TASK_STACK_FILE_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _write_stack_locked(stack: dict[str, list[dict]]) -> None:
    LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)
    TASK_STACK_FILE_PATH.write_text(json.dumps(stack, ensure_ascii=True, indent=2), encoding="utf-8")


def _log_generated_task(payload: TaskGenerationRequest, difficulty: Difficulty, task: TaskGenerationResponse, storage_mode: str) -> None:
    LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "storage_mode": storage_mode,
        "stack_key": _task_stack_key(payload, difficulty),
        "interaction_type": payload.interaction_type,
        "level_theme": payload.level_theme,
        "difficulty": difficulty,
        "generation_source": task.generation_source,
        "generation_detail": task.generation_detail,
        "pattern_id": task.pattern_id,
        "title": task.title,
        "prompt": task.prompt,
        "keywords": task.keywords,
        "validation_targets": task.validation_targets,
    }
    with TASK_HISTORY_FILE_PATH.open("a", encoding="utf-8") as log_file:
        log_file.write(json.dumps(record, ensure_ascii=True) + "\n")


def _log_generation_failure(payload: TaskGenerationRequest, difficulty: Difficulty, detail: str) -> None:
    LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)
    stack_key = _task_stack_key(payload, difficulty)
    with _TASK_STACK_LOCK:
        _TASK_STACK_FAILURES[stack_key] = _friendly_generation_failure(detail)
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "storage_mode": "prewarm_failed",
        "stack_key": stack_key,
        "interaction_type": payload.interaction_type,
        "level_theme": payload.level_theme,
        "difficulty": difficulty,
        "detail": detail,
    }
    with TASK_HISTORY_FILE_PATH.open("a", encoding="utf-8") as log_file:
        log_file.write(json.dumps(record, ensure_ascii=True) + "\n")


def _empty_stack_detail(payload: TaskGenerationRequest, difficulty: Difficulty) -> str:
    stack_key = _task_stack_key(payload, difficulty)
    with _TASK_STACK_LOCK:
        last_failure = _TASK_STACK_FAILURES.get(stack_key, "")
    if last_failure:
        return last_failure
    return "AI task stack is preparing; using a local pattern for this task"


def _friendly_generation_failure(detail: str) -> str:
    normalized = detail.strip()
    lowered = normalized.lower()
    if "403" in lowered or "access denied" in lowered or "forbidden" in lowered:
        return "AI provider denied model access; using a local pattern"
    if "429" in lowered or "rate limit" in lowered or "cooldown" in lowered:
        return "AI provider rate limit; using a local pattern"
    if "missing" in lowered and "key" in lowered:
        return "AI key is missing; using a local pattern"
    if "timed out" in lowered or "timeout" in lowered:
        return "AI request timed out; using a local pattern"
    if "invalid" in lowered or "parsing" in lowered:
        return "AI returned invalid data; using a local pattern"
    if not normalized:
        return "AI generation failed; using a local pattern"
    return "AI generation failed: %s" % normalized[:90]


def _build_patterns(theme: LevelTheme) -> list[dict[str, object]]:
    base = BASES[theme]
    out: list[dict[str, object]] = []
    for index, spec in enumerate(SPECS[theme]):
        targets = _norm(spec["v"])
        expanded_targets: list[str] = _expand_validation_targets(targets)
        prompt_text: str = _apply_readable_naming_guidance(theme, str(spec["p"]), targets)
        out.append({
            "pattern_id": "%s_%02d" % (theme, index + 1),
            "title": str(spec["t"]),
            "prompt": prompt_text,
            "gameplay_effect": _effect(theme),
            "explanation_title": str(base["title"]),
            "explanation_body": "%s Focus on concepts like %s." % (str(base["body"]), ", ".join(_display_concepts(targets))),
            "explanation_rules": list(base["rules"]),
            "explanation_prompt": _explanation_prompt(theme, targets),
            "syntax_rules": _syntax_rules(theme),
            "keywords": _merge_unique_terms(_norm(spec["k"]), _display_concepts(targets)),
            "example_code": str(spec["e"]),
            "fallback_hints": _fallback_hints(theme, targets),
            "validation_targets": expanded_targets,
        })
    return out


def _build_altar_patterns(theme: LevelTheme) -> list[dict[str, object]]:
    base = BASES[theme]
    out: list[dict[str, object]] = []
    for index, focus in enumerate(ALTAR_FOCI):
        first: str = str(focus["a"])
        second: str = str(focus["b"])
        action: str = str(focus["action"])
        targets: list[str] = _altar_targets_for_theme(theme, first, second, action)
        expanded_targets: list[str] = _expand_validation_targets(targets)
        display: list[str] = _display_concepts([first, second])
        focus_name: str = str(focus["name"])
        out.append({
            "pattern_id": "%s_altar_%02d" % (theme, index + 1),
            "title": "Forge Altar | %s" % focus_name,
            "prompt": _altar_prompt(theme, focus_name, first, second, action),
            "gameplay_effect": _altar_effect(theme, display),
            "explanation_title": "%s at the Forge" % str(base["title"]),
            "explanation_body": _altar_explanation_body(theme, str(base["body"]), display),
            "explanation_rules": _altar_rules(theme),
            "explanation_prompt": _altar_explanation_prompt(theme, display),
            "syntax_rules": _syntax_rules(theme),
            "keywords": _merge_unique_terms(_display_concepts([first, second]), _norm([focus_name, action, "forge altar", "weapon"])),
            "example_code": _altar_example(theme, str(focus["example"]), action),
            "fallback_hints": _altar_hints(theme, display),
            "validation_targets": expanded_targets,
        })
    return out


def _build_boss_pattern(payload: TaskGenerationRequest, base_pattern: dict[str, object]) -> dict[str, object]:
    transformed: dict[str, object] = base_pattern.copy()
    encounter: str = payload.encounter_name or "the boss"
    mechanic: str = payload.boss_mechanic.replace("_", " ").strip() if payload.boss_mechanic else "the next boss mechanic"
    style: str = payload.encounter_style.replace("_", " ").strip() if payload.encounter_style else "boss pattern"
    targets: list[str] = _norm(transformed.get("validation_targets", []))
    display: list[str] = _display_concepts(targets[:3]) if targets else ["timing", "pressure"]
    transformed["prompt"] = (
        "During the fight with %s, write code for the %s pattern. "
        "Keep it tied to %s and to %s."
    ) % (
        encounter,
        style,
        mechanic,
        ", ".join(display),
    )
    transformed["gameplay_effect"] = "A correct boss snippet directly weakens %s during %s." % (encounter, mechanic)
    transformed["explanation_body"] = (
        "%s In this boss room, every line must respond to %s and support the %s pattern."
    ) % (str(transformed.get("explanation_body", "")).rstrip("."), mechanic, style)
    transformed["explanation_prompt"] = (
        "Read the boss task for state words, boss-pattern words, and theme words, then convert only those clues into code."
    )
    transformed["fallback_hints"] = [
        "Use %s as the main clue for what the boss code should control." % mechanic,
        "Keep the snippet tied to %s and the current theme instead of writing generic combat code." % encounter,
    ]
    transformed["keywords"] = _merge_unique_terms(_norm(transformed.get("keywords", [])), [encounter, mechanic, style])
    transformed["validation_targets"] = _merge_unique_terms(_norm(transformed.get("validation_targets", [])), [encounter, mechanic, style])
    return transformed


def _altar_targets_for_theme(theme: LevelTheme, first: str, second: str, action: str) -> list[str]:
    if theme == "variables":
        return ["weapon", first, second]
    if theme == "conditions":
        return ["if", "weapon", action, first]
    if theme == "loops":
        return ["loop", "weapon", action]
    if theme == "functions":
        return ["def", "call", "weapon", action]
    return ["assignment", "if", "weapon", action, first]


def _altar_prompt(theme: LevelTheme, focus_name: str, first: str, second: str, action: str) -> str:
    display = _display_concepts([first, second])
    if theme == "variables":
        names = ", ".join(_suggested_variable_names([first, second]))
        return (
            "At the forge altar, tune the %s by assigning values for %s and %s. "
            "Use readable variable names that clearly mean those weapon stats. Suggested name style: %s."
        ) % (focus_name, display[0], display[1], names)
    if theme == "conditions":
        return (
            "At the forge altar, write one if/else branch that chooses the %s weapon behavior when %s is needed, "
            "and a safer setup when %s matters more."
        ) % (action, display[0], display[1])
    if theme == "loops":
        return (
            "At the forge altar, write one short loop that repeats the %s forge pulse several times while tuning %s and %s."
        ) % (action, display[0], display[1])
    if theme == "functions":
        return (
            "At the forge altar, define and call one helper function for the %s weapon setup. "
            "The helper should clearly connect to %s and %s."
        ) % (action, display[0], display[1])
    return (
        "At the forge altar, combine a small stat setup with one decision so the weapon can handle %s and %s during the next fight."
    ) % (display[0], display[1])


def _altar_effect(theme: LevelTheme, display: list[str]) -> str:
    if theme == "variables":
        return "A correct forge snippet changes the weapon stats for %s and %s." % (display[0], display[1])
    if theme == "conditions":
        return "A correct branch selects the forged weapon behavior for the current combat state."
    if theme == "loops":
        return "A correct loop repeats a controlled forge pulse and strengthens the next weapon window."
    if theme == "functions":
        return "A correct helper packages the forged weapon setup into a reusable tactic."
    return "A correct mixed forge snippet combines weapon stats and a tactical decision."


def _altar_explanation_body(theme: LevelTheme, base_body: str, display: list[str]) -> str:
    return (
        "%s At the altar, the code is not abstract: it forges a weapon setup. "
        "Read the requested weapon concepts, especially %s and %s, then write only the structure for this level theme."
    ) % (base_body.rstrip("."), display[0], display[1])


def _altar_explanation_prompt(theme: LevelTheme, display: list[str]) -> str:
    if theme == "variables":
        return "Look for the two weapon-stat phrases, then turn each phrase into one clear assignment."
    if theme == "conditions":
        return "Look for the weapon state and the alternative state, then turn that choice into one branch."
    if theme == "loops":
        return "Look for the repeated forge action and the repeat limit, then turn both into one loop."
    if theme == "functions":
        return "Look for the reusable forge action, name it clearly, define it, and call it."
    return "Look for the weapon stats and the decision point, then combine those ideas without adding unrelated code."


def _altar_rules(theme: LevelTheme) -> list[str]:
    if theme == "variables":
        return ["Use clear weapon-stat assignments.", "Similar meaningful names are accepted.", "Keep values reasonable."]
    if theme == "conditions":
        return ["Use one readable if/else branch.", "Both paths should be weapon behaviors.", "Do not add unrelated loops."]
    if theme == "loops":
        return ["Use one controlled loop.", "Repeat a forge or weapon action.", "Avoid endless loops."]
    if theme == "functions":
        return ["Define the helper first.", "Call the helper once.", "Keep the helper about weapon setup."]
    return ["Combine only useful constructs.", "Keep the weapon tactic compact.", "Make each part support the forge result."]


def _altar_hints(theme: LevelTheme, display: list[str]) -> list[str]:
    if theme == "variables":
        return [
            "Write one assignment for %s and one assignment for %s." % (display[0], display[1]),
            "Names can be approximate, but they should clearly sound like weapon stats.",
        ]
    if theme == "conditions":
        return ["Make the if condition choose between two weapon behaviors.", "Use the task's two weapon concepts as branch clues."]
    if theme == "loops":
        return ["Start with the forge action, then wrap it in a small range loop.", "The loop should repeat a weapon action, not random code."]
    if theme == "functions":
        return ["Name the helper after the forge action, define it with def, then call it.", "Keep the helper focused on the requested weapon concepts."]
    return ["Use one stat setup and one tactical structure.", "Every line should support the same forged weapon result."]


def _altar_example(theme: LevelTheme, variable_example: str, action: str) -> str:
    if theme == "variables":
        return variable_example
    if theme == "conditions":
        return "if weapon_ready:\n    action = '%s'\nelse:\n    action = 'guard'" % action
    if theme == "loops":
        return "for _ in range(3):\n    %s()" % action
    if theme == "functions":
        return "def forge_%s():\n    weapon_ready = True\n\nforge_%s()" % (action, action)
    return "weapon_power = 12\nif weapon_ready:\n    %s()" % action


def _bossify(pattern: dict[str, object], payload: TaskGenerationRequest) -> dict[str, object]:
    idx = max(0, int(str(pattern["pattern_id"]).split("_")[-1]) - 1)
    encounter = payload.encounter_name or "the boss"
    mechanic = payload.boss_mechanic.replace("_", " ").strip() if payload.boss_mechanic else "the next boss mechanic"
    flavor = BOSS_FLAVORS[payload.level_theme][idx]
    transformed = pattern.copy()
    transformed["pattern_id"] = "%s_boss_%02d" % (payload.level_theme, idx + 1)
    transformed["title"] = "%s | %s" % (encounter, flavor)
    transformed["prompt"] = "Against %s, %s Keep the answer tied to %s." % (encounter, str(pattern["prompt"]).rstrip(".").lower() + ".", mechanic)
    transformed["gameplay_effect"] = "A correct snippet directly affects %s during %s." % (encounter, mechanic)
    transformed["explanation_prompt"] = "Read the boss task for state words, action words, and stat words, then turn them into code without leaving the current theme."
    transformed["explanation_body"] = "%s The boss context matters here: %s should change how you read the task." % (str(pattern["explanation_body"]).rstrip("."), mechanic.capitalize())
    transformed["fallback_hints"] = [
        "Tie the code to %s and keep the structure inside the current theme." % encounter,
        "Use %s as a clue for which concepts matter most in the task." % mechanic,
    ]
    transformed["validation_targets"] = _merge_unique_terms(_norm(pattern["validation_targets"]), [encounter, mechanic])
    return transformed


def _effect(theme: LevelTheme) -> str:
    if theme == "variables":
        return "A correct snippet tunes the requested combat stats for the next exchange."
    if theme == "conditions":
        return "A correct branch makes the knight choose the right action for the current state."
    if theme == "loops":
        return "A correct loop repeats the requested action with control during the next combat window."
    if theme == "functions":
        return "A correct helper creates a reusable tactic for the next combat response."
    return "A correct mixed snippet combines several tools into one stronger tactical response."


def _explanation_prompt(theme: LevelTheme, targets: list[str]) -> str:
    focus = ", ".join(_display_concepts(targets))
    if theme == "variables":
        return "Read the stat words in the task, then map each important concept into one assignment line with a clear descriptive variable name. Focus on %s." % focus
    if theme == "conditions":
        return "Find the state clue and the action clue in the task, then translate them into one readable branch. Focus on %s." % focus
    if theme == "loops":
        return "Find the repetition clue and the stopping clue in the task text, then translate both into one loop. Focus on %s." % focus
    if theme == "functions":
        return "Find the reusable action in the task text, turn it into one helper name, then define and call it. Focus on %s." % focus
    return "Use the task words as a checklist for which constructs should appear together. Focus on %s." % focus


def _syntax_rules(theme: LevelTheme) -> list[str]:
    if theme == "variables":
        return ["Use assignments only.", "Keep one concept per line.", "Avoid conditions, loops, and functions."]
    if theme == "conditions":
        return ["Use at least one if/else branch.", "Keep the branch readable.", "Choose or assign an action inside the branch."]
    if theme == "loops":
        return ["Use one loop as the main structure.", "Keep the loop body short.", "Make the stop rule obvious."]
    if theme == "functions":
        return ["Define one function with def.", "Call the function after defining it.", "Keep the helper focused."]
    return ["Use at least two core constructs.", "Keep the snippet compact.", "Make each part contribute to the same tactic."]


def _fallback_hints(theme: LevelTheme, targets: list[str]) -> list[str]:
    preview = ", ".join(_display_concepts(targets))
    if theme == "variables":
        return ["Start by defining the requested stats directly: %s." % preview, "Use one assignment per line and choose readable names that clearly mean those gameplay concepts."]
    if theme == "conditions":
        return ["Write the condition first, then decide what each branch should do for %s." % preview, "Keep one action or result in each branch."]
    if theme == "loops":
        return ["Write the repeated action first, then wrap it in one loop tied to %s." % preview, "Keep the body short and make the repeat rule visible."]
    if theme == "functions":
        return ["Name the helper around %s, define it with def, then call it." % preview, "Do not duplicate the repeated action outside the helper."]
    return ["Use the task words as a checklist and include at least two constructs around %s." % preview, "Keep the snippet readable and do not add extra code that does not support the tactic."]


def _context_prompt(prompt: str, payload: TaskGenerationRequest) -> str:
    if payload.interaction_type == "boss":
        return prompt
    parts = [prompt.rstrip(".")]
    if payload.gameplay_context:
        parts.append("This one is framed around %s" % str(payload.gameplay_context).rstrip("."))
    if payload.structure_focus:
        parts.append("Aim for %s" % str(payload.structure_focus).rstrip("."))
    return ". ".join(parts) + "."


def _context_effect(effect: str, payload: TaskGenerationRequest) -> str:
    if payload.interaction_type != "boss" and payload.encounter_name:
        return "%s It is tied to %s." % (effect.rstrip("."), payload.encounter_name)
    return effect


def _context_explanation(body: str, payload: TaskGenerationRequest) -> str:
    if payload.interaction_type == "boss":
        return body
    if payload.encounter_style:
        return "%s This encounter plays like a %s situation." % (body.rstrip("."), payload.encounter_style)
    return body


def _context_explanation_prompt(prompt: str, payload: TaskGenerationRequest) -> str:
    if payload.interaction_type == "boss":
        return prompt
    if payload.encounter_name:
        return "%s Pay special attention to words connected with %s." % (prompt.rstrip("."), payload.encounter_name)
    return prompt


def _scale_example(example: str, difficulty: Difficulty) -> str:
    if difficulty == "easy":
        return example
    if difficulty == "normal":
        return example.replace(" = 1", " = 2").replace("range(2)", "range(3)")
    return example.replace(" = 2", " = 3").replace("range(3)", "range(4)").replace("range(2)", "range(3)")


def _norm(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _expand_validation_targets(targets: list[str]) -> list[str]:
    expanded: list[str] = []
    for target in targets:
        target_text: str = target.strip()
        if not target_text:
            continue
        if target_text not in expanded:
            expanded.append(target_text)
        for alias in CONCEPT_ALIASES.get(target_text, []):
            if alias not in expanded:
                expanded.append(alias)
    return expanded


def _display_concepts(targets: list[str]) -> list[str]:
    display_terms: list[str] = []
    for target in targets[:3]:
        aliases: list[str] = CONCEPT_ALIASES.get(target, [])
        display_terms.append(aliases[0] if aliases else target.replace("_", " "))
    return display_terms


def _apply_readable_naming_guidance(theme: LevelTheme, prompt: str, targets: list[str]) -> str:
    if theme != "variables":
        return prompt
    readable_focus: str = ", ".join(_display_concepts(targets))
    suggested_names: str = ", ".join(_suggested_variable_names(targets))
    return "%s Use readable variable names that clearly mean %s. Suggested name style: %s." % (
        prompt.rstrip("."),
        readable_focus,
        suggested_names,
    )


def _merge_unique_terms(primary: list[str], secondary: list[str]) -> list[str]:
    merged: list[str] = []
    for collection in [primary, secondary]:
        for item in collection:
            text: str = str(item).strip()
            if text and text not in merged:
                merged.append(text)
    return merged


def _suggested_variable_names(targets: list[str]) -> list[str]:
    suggestions: list[str] = []
    for target in targets[:3]:
        aliases: list[str] = CONCEPT_ALIASES.get(target, [])
        if target and target not in suggestions:
            suggestions.append(target)
        for alias in aliases[:2]:
            candidate: str = alias.lower().replace(" ", "_").replace("-", "_")
            if candidate and candidate not in suggestions:
                suggestions.append(candidate)
        if len(suggestions) >= 4:
            break
    return suggestions if suggestions else ["clear_stat_name"]
