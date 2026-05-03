extends Node

# MutatorManager handles gameplay modifiers that alter the game's mechanics.

enum Mutator {
    NONE,
    MIRROR_MODE,
    CHAOS_MODE,
    TURBO_MODE
}

var active_mutators: Array[Mutator] = []

func _ready():
    # Example: Check settings for active mutators
    pass

func is_mutator_active(mutator: Mutator) -> bool:
    return active_mutators.has(mutator)

func toggle_mutator(mutator: Mutator, enabled: bool):
    if enabled and not active_mutators.has(mutator):
        active_mutators.append(mutator)
    elif not enabled and active_mutators.has(mutator):
        active_mutators.erase(mutator)
    
    _apply_mutator_side_effects()

func _apply_mutator_side_effects():
    # Handle global state changes for specific mutators
    if is_mutator_active(Mutator.TURBO_MODE):
        Engine.time_scale = 1.2
    else:
        Engine.time_scale = 1.0

func _input(event):
    if is_mutator_active(Mutator.MIRROR_MODE):
        # This is a simplified example of how we might intercept input.
        # In a real scenario, we'd need to hook into the game's specific input handler.
        pass
