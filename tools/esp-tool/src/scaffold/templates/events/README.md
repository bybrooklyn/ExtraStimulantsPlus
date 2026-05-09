# {{name}}

Built on the [ExtraStimulantsPlus](https://github.com/bybrooklyn/extrastimulantsplus) framework. Demonstrates **event hooks**.

This mod listens for `level_started`, `obstacle_passed`, and (one-shot) `score_updated`. The first two are declared in `mod.json::hooks.events`; the third uses imperative `api.events.once()`.

See `main.gd` for inline comments and signatures. The full event list lives in the framework at `scripts/core/esp_event_adapter.gd::GAME_EVENT_MAP`.
