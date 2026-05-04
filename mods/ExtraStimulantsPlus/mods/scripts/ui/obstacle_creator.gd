extends Control

@onready var grid_container = %GridContainer
@onready var name_edit = %NameEdit
@onready var save_btn = %SaveBtn
@onready var close_btn = %CloseBtn

var _cells: Dictionary = {}
var _library: ObstacleDefinitionLibrary

func _ready():
    _library = ObstacleDefinitionLibrary.new()
    _library.setup(10.0)
    
    save_btn.pressed.connect(_on_save_pressed)
    close_btn.pressed.connect(_on_close_pressed)
    
    _build_grid()

func _build_grid():
    for c in grid_container.get_children():
        c.queue_free()
        
    _cells.clear()
    
    # 21x21 grid, center is (0,0), so -10 to 10
    grid_container.columns = 21
    
    for y in range(-10, 11):
        for x in range(-10, 11):
            var btn = Button.new()
            btn.custom_minimum_size = Vector2(24, 24)
            btn.toggle_mode = true
            btn.toggled.connect(_on_cell_toggled.bind(Vector2i(x, y)))
            grid_container.add_child(btn)
            _cells[Vector2i(x, y)] = btn

func _on_cell_toggled(toggled_on: bool, pos: Vector2i):
    if UiSfxManager: UiSfxManager.play_hover()

func _on_save_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    var display_name = name_edit.text.strip_edges()
    if display_name == "": return
    
    var def = CustomObstacleDefinition.new()
    def.id = "custom_" + display_name.to_lower().replace(" ", "_")
    def.display_name = display_name
    
    for pos in _cells:
        if _cells[pos].button_pressed:
            def.filled_cells.append(pos)
            
    if def.filled_cells.is_empty(): return
    
    _library.save_definition(def)
    
    # Close
    queue_free()

func _on_close_pressed():
    if UiSfxManager: UiSfxManager.play_back()
    queue_free()
