extends "res://scripts/campaign/campaign_level_loader.gd"

# ESP Campaign Level Loader Extension
# Automatically injects custom .somap levels from the registry into the game's lists.

static func load_all_levels(dir_path: String = LEVELS_DIR) -> Array[CampaignLevelDef]:
    var levels = super.load_all_levels(dir_path)
    
    # Inject custom levels from ESP
    var esp = Engine.get_main_loop().root.get_node_or_null("/root/ESP")
    if esp and esp.level_registry:
        esp.level_registry.scan_custom_levels()
        esp.level_registry.inject_levels(levels)
        
    return levels
