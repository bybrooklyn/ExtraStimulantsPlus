# {{name}}

Built on the [ExtraStimulantsPlus](https://github.com/bybrooklyn/extrastimulantsplus) framework. Demonstrates **typed settings**.

This mod declares three settings (`enabled`, `intensity`, `label_text`) under the `gameplay.example.*` group. They appear automatically under SO's settings menu in the MODS tab, with native-looking controls per type.

Supported types: `boolean`, `int`, `float`, `string`. Add `min`/`max`/`step` for numeric types to constrain the SpinBox range. Groups can nest arbitrarily deep — each level needs `label` + `settings`.

`main.gd` shows how to (a) read settings at runtime and (b) subscribe to live changes via the registry's `setting_changed` signal.
