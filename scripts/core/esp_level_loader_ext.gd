extends "res://scripts/campaign/campaign_level_loader.gd"

# ESP Campaign Level Loader Extension
# Injects framework-managed custom levels through the campaign adapter.

static func load_all_levels(dir_path: String = LEVELS_DIR) -> Array[CampaignLevelDef]:
    var levels = super.load_all_levels(dir_path)
    
    var root := Engine.get_main_loop().root
    var campaign_adapter := root.get_node_or_null("/root/ESPCampaignAdapter")
    if campaign_adapter and campaign_adapter.has_method("inject_registered_levels"):
        campaign_adapter.inject_registered_levels(levels)
        return levels

    var esp = root.get_node_or_null("/root/ESP")
    if esp and esp.level_registry:
        esp.level_registry.scan_custom_levels()
        esp.level_registry.inject_levels(levels)
        
    return levels
