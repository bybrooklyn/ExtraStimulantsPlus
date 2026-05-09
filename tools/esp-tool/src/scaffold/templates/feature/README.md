# {{name}}

Built on the [ExtraStimulantsPlus](https://github.com/bybrooklyn/extrastimulantsplus) framework. Demonstrates the **feature-node pattern**.

A "feature node" is a long-lived Node installed under `/root/` that the mod configures with `(api, meta)`. It owns a slice of behavior — audio sampling, ghost recording, an effect controller, etc. — and receives lifecycle events from the framework's event hooks.

`main.gd` instantiates `scripts/core/example_feature.gd` at `/root/ExampleFeature`. The feature subscribes to `level_started`/`level_completed`/`player_died` and gates its work on whether a level is active.

For a fuller worked example, see `mods/ExtraStimulantsPlus/mods/scripts/core/rt_effects.gd` in the framework repo.
