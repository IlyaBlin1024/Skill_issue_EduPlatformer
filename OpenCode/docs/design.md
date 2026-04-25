# CodeKnight Design Document

This file captures the current project vision and is based on the approved design outline for the educational experiment.

## Core Concept

- Title: CodeKnight
- Genre: 2D action-platformer with programming encounters
- Engine: Godot 4.x with GDScript
- AI backend: Python 3.13+, FastAPI, Transformers, scikit-learn
- Audience: first-year undergraduate programming students

## Sprint Breakdown

### Sprint 1

- Player controller
- Encounter pause system
- Combat Terminal UI
- Basic backend connectivity

### Sprint 2

- Adaptive difficulty tuning
- AI hint improvements
- Combat timing rules

### Sprint 3

- Enemy and boss behaviour
- Tactical boss scripting
- Pause cooldown systems

### Sprint 4

- Content production
- Logging pipeline
- Experiment-readiness polish

## Current Implementation Notes

- Combat validation is currently syntax-first and lightweight.
- Hint generation is rule-based for now and can be replaced by an LLM-backed service later.
- The Godot scenes are intentionally minimal so mechanics can be proven before content production.
