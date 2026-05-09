# {{name}}

Built on the [ExtraStimulantsPlus](https://github.com/bybrooklyn/extrastimulantsplus) framework. Demonstrates **custom levels**.

This mod ships an example level at `levels/example.json` and resolves the path at startup via `api.assets.resolve(meta, ...)`. To actually play it, call `play_custom_level_path()` (currently commented out in `esp_ready`) or trigger it from a UI button.

The bundled level editor (accessible via the "CUSTOM MAPS" button on the main menu) writes JSON files in the right schema. Easiest workflow: design in the editor, export, drop the file under `levels/`.
