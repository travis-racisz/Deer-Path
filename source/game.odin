package game

import "core:c"
import "core:container/queue"
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "core:strings"
// import "core:time"
import "core:math"
import rl "vendor:raylib"


// GLOBALS
run: bool
texture: rl.Texture
texture2: rl.Texture
current_level: int = 0
screen_height: i32
screen_width: i32
background_texture: rl.RenderTexture2D
mouse_pos: rl.Vector2
selected_tile: TileType
level: [LEVEL_COUNT]Level
level_grid_copy: Level
player_position: rl.Vector2
target_position: rl.Vector2
player_speed: f32 = 3.0
current_path_index: int = 0
is_animating: bool = false
animation_done: bool = false
current_turn: int = 0
game_over: bool = false
game_over_reason: string = ""
player_won: bool = false
fire_spread_chance: f32 = 0.2 // Chance for fire to spread each turn
turn_delay_timer: f32 = 0
turn_delay_duration: f32 = 0.15
move_in_progress: bool = false
move_progress: f32 = 0.0 // 0.0 to 1.0 for movement interpolation
previous_position: rl.Vector2
current_game_state: GameState = .Title_Screen
fire_animation_timer: f32 = 0
fire_animation_speed: f32 = 0.1
fire_animation_frame: int = 0
sprite_assets: SpriteAssets
placed_path_tiles: [dynamic]PathTile // Tiles as placed by player
movement_path: [dynamic]PathTile
is_path_valid: bool = false
ripple_shader: rl.Shader
target: rl.RenderTexture2D
update_render_target: bool = true
// -------- GIF Stuff ---------------
end_gif_frames: i32 = 7
current_gif_frame: i32 = 0
frame_delay := 400
frame_counter := 0
// -----------------------------------
TILE_SIZE :: 64
offset_x := f32(rl.GetScreenWidth() / 2 + TILE_SIZE * 10)
offset_y := f32(rl.GetScreenHeight() / 2 - TILE_SIZE)

// TODO: Add tutorial for the player to click through on the first level
// make it skipable 
// add more levels 
// add start and end tile sprites 
// add predator sprites 
// add music 
// add some sound effects 
// add better background for fire tile 
// add a path tile as well 

ripple_texture: rl.Texture

camera: rl.Camera2D

tile_placement_anim: struct {
	active:     bool,
	position:   rl.Vector2,
	start_time: f32,
	duration:   f32,
}

SpriteAssets :: struct {
	fire:           [8]rl.Texture,
	grass:          rl.Texture,
	deer:           rl.Texture,
	charred_ground: rl.Texture,
	dirt:           rl.Texture,
	end:            rl.Texture,
	start:          rl.Texture,
}

Level :: struct {
	grid:                [10][10]TileType,
	start_position:      rl.Vector2,
	end_position:        rl.Vector2,
	available_resources: ResourceSet,
	level_name:          string,
	level_number:        i32,
}

PathTile :: struct {
	row: int,
	col: int,
}


TileType :: enum {
	Empty,
	Grass,
	Meadow,
	Road,
	Predator,
	Fire,
	Path,
	HuntZone,
	Dirt,
	Bridge,
}


ResourceSet :: struct {
	path_tiles:     i32,
	dirt_tiles:     i32,
	bridge_tiles:   i32,
	hunting_ground: i32,
}

LEVEL_COUNT :: 4


GameState :: enum {
	Title_Screen,
	Instructions_Screen,
	Gameplay,
	EndGame,
	Tutorial,
}

shaders: struct {
	path_flow:                rl.Shader,
	fire_distortion:          rl.Shader,
	tile_placement:           rl.Shader,
	crt_effect:               rl.Shader,
	trippy_background:        rl.Shader,

	// Shader uniforms
	texture0_loc:             i32,
	path_flow_time_loc:       i32,
	path_flow_resolution_loc: i32,
	fire_time_loc:            i32,
	fire_texture0_loc:        i32,
	tile_time_loc:            i32,
	tile_resolution_loc:      i32,
	crt_resolution_loc:       i32,
	crt_time_loc:             i32,
	crt_texture0_loc:         i32,
	tile_pos_loc:             i32,
	trippy_time_loc:          i32,
	trippy_resolution_loc:    i32,
	trippy_texture0_loc:      i32,
}

Particle :: struct {
	position:     rl.Vector2,
	velocity:     rl.Vector2,
	acceleration: rl.Vector2,
	color:        rl.Color,
	size:         f32,
	life:         f32,
	max_life:     f32,
	active:       bool,
}
FireEffect :: struct {
	fire_texture:   rl.Texture2D,
	position:       rl.Vector2,
	shader:         rl.Shader,
	embers:         [50]Particle,
	smoke:          [30]Particle,
	glow_radius:    f32,
	glow_color:     rl.Color,
	glow_intensity: f32,
	base_texture:   rl.Texture2D,
}

TutorialStep :: struct {
	message:        string,
	target_area:    rl.Rectangle,
	highlight:      bool,
	wait_for_input: bool,
	input_type:     enum {
		Click,
		Key,
		Any,
		None,
	},
	key:            rl.KeyboardKey,
	completed:      bool,
}

// Tutorial system globals
tutorial: struct {
	active:          bool,
	current_step:    int,
	steps:           [dynamic]TutorialStep,
	overlay_opacity: f32,
	highlight_size:  f32,
	pulse_timer:     f32,
}

// Initialize the tutorial system
init_tutorial :: proc() {
	clear_dynamic_array(&tutorial.steps)
	tutorial.active = true
	tutorial.current_step = 0
	tutorial.overlay_opacity = 0.2
	tutorial.highlight_size = 5.0
	tutorial.pulse_timer = 0.0

	// Define all tutorial steps
	append(
		&tutorial.steps,
		TutorialStep {
			message = "Welcome to Deer Path! In this game, you'll help a deer navigate safely through dangerous environments.",
			target_area = {0, 0, f32(screen_width), f32(screen_height)},
			highlight = false,
			wait_for_input = true,
			input_type = .Any,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "This is the Start. Your goal is to guide the deer to safely from the start position to the end goal.",
			target_area = {
				f32(level[current_level].start_position.x * TILE_SIZE + offset_x - 32),
				f32(level[current_level].start_position.y * TILE_SIZE - offset_y - 32),
				128,
				128,
			},
			highlight = true,
			wait_for_input = true,
			input_type = .Any,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "This is the end goal. The deer needs to reach this point.",
			target_area = {
				f32(level[current_level].end_position.x * TILE_SIZE + offset_x - 32),
				f32(level[current_level].end_position.y * TILE_SIZE - offset_y - 32),
				128,
				128,
			},
			highlight = true,
			wait_for_input = true,
			input_type = .Any,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "This is your resource panel. It shows how many path tiles you have available.",
			target_area = {20, 70, 160, 100},
			highlight = true,
			wait_for_input = true,
			input_type = .Any,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "Select the Path Tile tool to start building a path for the deer.",
			target_area = {50, 230, 50, 50},
			highlight = true,
			wait_for_input = true,
			input_type = .Click,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "Now click on the grid to place path tiles. Create a path from start to end.",
			target_area = {f32(offset_x), f32(-offset_y), 640, 640},
			highlight = true,
			wait_for_input = false,
			input_type = .None,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message        = "Watch out for fire! It spreads each turn and will harm the deer.",
			target_area    = {0, 0, 0, 0}, // We'll update this dynamically to highlight fire tiles
			highlight      = true,
			wait_for_input = true,
			input_type     = .Any,
			completed      = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "Once your path is complete, press SPACE to start the deer's journey.",
			target_area = {0, 0, f32(screen_width), f32(screen_height)},
			highlight = false,
			wait_for_input = true,
			input_type = .Key,
			key = .SPACE,
			completed = false,
		},
	)

	append(
		&tutorial.steps,
		TutorialStep {
			message = "Congratulations! You've completed the tutorial. Press any key to continue to the game.",
			target_area = {0, 0, f32(screen_width), f32(screen_height)},
			highlight = false,
			wait_for_input = true,
			input_type = .Any,
			completed = false,
		},
	)
}

update_tutorial :: proc() {
	if !tutorial.active || tutorial.current_step >= len(tutorial.steps) {
		return
	}

	// Update pulse effect for highlights
	tutorial.pulse_timer += rl.GetFrameTime()
	// pulse_factor := math.sin_f32(tutorial.pulse_timer * 4.0) * 0.2 + 0.8

	// Get current step
	current := &tutorial.steps[tutorial.current_step]

	// For fire tile tutorial step
	if tutorial.current_step == 6 {
		// Find a fire tile to highlight
		found_fire := false
		for row in 0 ..< 10 {
			for col in 0 ..< 10 {
				if level[current_level].grid[row][col] == .Fire {
					current.target_area = {
						f32(col * TILE_SIZE + int(offset_x) - 16),
						f32(row * TILE_SIZE - int(offset_y) - 16),
						96,
						96,
					}
					found_fire = true
					break
				}
			}
			if found_fire do break
		}
	}

	// Check for step completion
	if current.wait_for_input {
		#partial switch current.input_type {
		case .Click:
			if rl.IsMouseButtonPressed(.LEFT) &&
			   rl.CheckCollisionPointRec(mouse_pos, current.target_area) {
				current.completed = true
				tutorial.current_step += 1
			}
		case .Key:
			if rl.IsKeyPressed(current.key) {
				current.completed = true
				tutorial.current_step += 1
			}
		case .Any:
			if rl.IsMouseButtonPressed(.LEFT) || rl.IsKeyPressed(.ENTER) {
				current.completed = true
				tutorial.current_step += 1
			}
		}
	} else {
		// For the path building step, check if a valid path has been created
		if tutorial.current_step == 5 && is_path_valid {
			current.completed = true
			tutorial.current_step += 1
		}
	}
}

// Draw tutorial overlays and messages
draw_tutorial :: proc() {
	if !tutorial.active || tutorial.current_step >= len(tutorial.steps) {
		return
	}

	current := tutorial.steps[tutorial.current_step]

	// Draw darkened overlay for everything except highlighted area
	rl.DrawRectangle(
		0,
		0,
		screen_width,
		screen_height,
		{0, 0, 0, u8(tutorial.overlay_opacity * 180)},
	)

	// Draw highlighted area
	if current.highlight {
		// Calculate pulse effect
		pulse_amount := math.sin_f32(tutorial.pulse_timer * 4.0) * 10.0
		highlight_rect := current.target_area

		// Clear the highlight area
		rl.DrawRectangleRec(highlight_rect, {0, 0, 0, 0})

		// Draw a pulsing border around the highlight area
		rl.DrawRectangleLinesEx(
			{
				highlight_rect.x - pulse_amount,
				highlight_rect.y - pulse_amount,
				highlight_rect.width + pulse_amount * 2,
				highlight_rect.height + pulse_amount * 2,
			},
			tutorial.highlight_size,
			{255, 255, 0, 255},
		)
	}

	// Draw message box
	message_width: i32 = 200
	message_height := 100
	message_x := (screen_width - message_width) / 2
	message_y := screen_height - i32(message_height - 50)

	rl.DrawRectangleRounded(
		{f32(message_x), f32(message_y), f32(message_width), f32(message_height)},
		0.2,
		10,
		{50, 50, 50, 230},
	)
	rl.DrawRectangleRoundedLines(
		{f32(message_x), f32(message_y), f32(message_width), f32(message_height)},
		0.2,
		10,
		rl.Color{255, 255, 255, 200},
	)

	// Draw message text with word wrapping
	rl.DrawText(
		strings.clone_to_cstring(tutorial.steps[tutorial.current_step].message),
		500,
		500,
		20,
		rl.WHITE,
	)


	// Draw continue prompt
	if current.wait_for_input {
		prompt_text: string
		#partial switch current.input_type {
		case .Click:
			prompt_text = "Click on the highlighted area to continue"
		case .Key:
			prompt_text = fmt.tprintf("Press %v to continue", current.key)
		case .Any:
			prompt_text = "Press any key or click to continue"
		}

		rl.DrawText(
			strings.clone_to_cstring(prompt_text),
			message_x +
			message_width / 2 -
			rl.MeasureText(strings.clone_to_cstring(prompt_text), 16) / 2,
			message_y + i32(message_height - 30),
			16,
			{255, 255, 150, 255},
		)
	}
}


trigger_tile_placement_effect :: proc(x, y: i32) {
	tile_placement_anim.active = true
	tile_placement_anim.position = {f32(x + 50), f32(y + 50)} // Center of tile
	tile_placement_anim.start_time = f32(rl.GetTime())
	tile_placement_anim.duration = 1.8 // Animation lasts 0.8 seconds
}

update_and_draw_tile_effects :: proc() {
	if tile_placement_anim.active {
		current_time := f32(rl.GetTime())
		elapsed := current_time - tile_placement_anim.start_time

		if elapsed > tile_placement_anim.duration {
			tile_placement_anim.active = false
		} else {
			// Normalize time to 0-1 range
			normalized_time := elapsed / tile_placement_anim.duration

			// Debug info
			fmt.println("Effect active - Time:", normalized_time)

			// Use shader-specific uniform locations
			rl.SetShaderValue(
				shaders.tile_placement,
				shaders.tile_time_loc,
				&normalized_time,
				.FLOAT,
			)

			// Draw effect without all the other parameters for now


		}
	}
}


init_shaders :: proc() {
	// Load shaders
	shaders.path_flow = rl.LoadShader(nil, "assets/shaders/path_flow.fs")
	shaders.fire_distortion = rl.LoadShader(nil, "assets/shaders/fire_distortion.fs")
	shaders.tile_placement = rl.LoadShader(nil, "assets/shaders/tile_placement.fs")
	shaders.texture0_loc = rl.GetShaderLocation(shaders.fire_distortion, "texture0")
	ripple_shader = rl.LoadShader(nil, "ripple.fs")

	fmt.println(
		"Shader IDPath:",
		shaders.path_flow.id,
		"Fire:",
		shaders.fire_distortion.id,
		"Tile:",
		shaders.tile_placement.id,
	)
	resolution := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	// If any shader ID is 0, the shader failed to load
	if shaders.tile_placement.id == 0 {
		fmt.println("ERROR: Tile placement shader failed to load")
	}

	// For path flow shader
	shaders.path_flow_time_loc = rl.GetShaderLocation(shaders.path_flow, "time")
	shaders.path_flow_resolution_loc = rl.GetShaderLocation(shaders.path_flow, "resolution")

	time := rl.GetTime()
	rl.SetShaderValue(ripple_shader, rl.GetShaderLocation(ripple_shader, "u_time"), &time, .FLOAT)

	// Load CRT shader - use your new browser-compatible shader
	shaders.crt_effect = rl.LoadShader(nil, "assets/shaders/crt_effect.fs")

	// Get uniform locations for CRT shader
	shaders.crt_resolution_loc = rl.GetShaderLocation(shaders.crt_effect, "resolution")
	shaders.crt_time_loc = rl.GetShaderLocation(shaders.crt_effect, "time")
	shaders.crt_texture0_loc = rl.GetShaderLocation(shaders.crt_effect, "texture0")

	// Set initial values for CRT shader
	rl.SetShaderValue(shaders.crt_effect, shaders.crt_resolution_loc, &resolution, .VEC2)
	rl.SetShaderValue(shaders.crt_effect, shaders.crt_texture0_loc, &[1]i32{0}, .INT)

	// For fire distortion shader
	shaders.fire_time_loc = rl.GetShaderLocation(shaders.fire_distortion, "time")
	shaders.fire_texture0_loc = rl.GetShaderLocation(shaders.fire_distortion, "texture0")

	// For tile placement shader
	shaders.tile_time_loc = rl.GetShaderLocation(shaders.tile_placement, "time")
	shaders.tile_pos_loc = rl.GetShaderLocation(shaders.tile_placement, "tilePos")
	shaders.tile_resolution_loc = rl.GetShaderLocation(shaders.tile_placement, "resolution")

	shaders.trippy_background = rl.LoadShader(nil, "assets/shaders/trippy_background.fs")

	// Get uniform locations for trippy background shader
	shaders.trippy_time_loc = rl.GetShaderLocation(shaders.trippy_background, "time")
	shaders.trippy_resolution_loc = rl.GetShaderLocation(shaders.trippy_background, "resolution")
	shaders.trippy_texture0_loc = rl.GetShaderLocation(shaders.trippy_background, "texture0")

	// Set initial values for trippy background shader
	rl.SetShaderValue(shaders.trippy_background, shaders.trippy_resolution_loc, &resolution, .VEC2)
	rl.SetShaderValue(shaders.trippy_background, shaders.trippy_texture0_loc, &[1]i32{0}, .INT)

	// Set initial values
	rl.SetShaderValue(shaders.path_flow, shaders.path_flow_resolution_loc, &resolution, .VEC2)
}

// Add this to your shutdown procedure
unload_shaders :: proc() {
	rl.UnloadShader(shaders.path_flow)
	rl.UnloadShader(shaders.fire_distortion)
	rl.UnloadShader(shaders.tile_placement)
}

find_path_bfs :: proc(start_row, start_col, end_row, end_col: int) -> [dynamic]PathTile {
	result_path := make([dynamic]PathTile)

	// Create a queue for BFS
	q: queue.Queue(PathTile)
	queue.init(&q)

	// Track visited tiles
	visited: [10][10]bool

	// Track parent tiles to reconstruct path
	parent: [10][10]PathTile

	// Start from the start position
	start := PathTile {
		row = start_row,
		col = start_col,
	}
	queue.push(&q, start)
	visited[start_row][start_col] = true

	// BFS to find path
	found_path := false
	for queue.len(q) > 0 && !found_path {
		current := queue.pop_front(&q)

		// Check if reached end
		if current.row == end_row && current.col == end_col {
			found_path = true

			// Reconstruct path
			path_tile := current
			for path_tile.row != start_row || path_tile.col != start_col {
				append(&result_path, path_tile)
				path_tile = parent[path_tile.row][path_tile.col]
			}
			append(&result_path, start)

			// Reverse path (from start to end)
			for i, j := 0, len(result_path) - 1; i < j; i, j = i + 1, j - 1 {
				result_path[i], result_path[j] = result_path[j], result_path[i]
			}

			break
		}

		// Check adjacent tiles
		directions := [][2]int{{0, 1}, {1, 0}, {0, -1}, {-1, 0}} // right, down, left, up

		for dir in directions {
			next_row := current.row + dir[0]
			next_col := current.col + dir[1]

			// Skip if out of bounds
			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}

			// Skip if already visited
			if visited[next_row][next_col] {
				continue
			}

			// Skip if not a path tile
			if level[current_level].grid[next_row][next_col] != .Path &&
			   !(next_row == end_row && next_col == end_col) {
				continue
			}

			// Add to queue
			next := PathTile {
				row = next_row,
				col = next_col,
			}
			queue.push(&q, next)
			visited[next_row][next_col] = true
			parent[next_row][next_col] = current
		}
	}

	// Clean up
	queue.destroy(&q)

	return result_path
}


load_sprites :: proc() {

	// load start tile 

	if start_data, ok := read_entire_file("assets/Start.png", context.temp_allocator); ok {
		start_img := rl.LoadImageFromMemory(".png", raw_data(start_data), c.int(len(start_data)))

		sprite_assets.start = rl.LoadTextureFromImage(start_img)
	}

	// load end tile 
	if end_data, ok := read_entire_file("assets/End.png", context.temp_allocator); ok {
		end_img := rl.LoadImageFromMemory(".png", raw_data(end_data), c.int(len(end_data)))

		sprite_assets.end = rl.LoadTextureFromImage(end_img)
	}

	// load dirt 

	if dirt_data, ok := read_entire_file("assets/Dirt.png", context.temp_allocator); ok {
		dirt_img := rl.LoadImageFromMemory(".png", raw_data(dirt_data), c.int(len(dirt_data)))

		sprite_assets.dirt = rl.LoadTextureFromImage(dirt_img)
	}
	// load charred ground 
	if charred_data, ok := read_entire_file("assets/charred_ground.png", context.temp_allocator);
	   ok {
		charred_img := rl.LoadImageFromMemory(
			".png",
			raw_data(charred_data),
			c.int(len(charred_data)),
		)

		sprite_assets.charred_ground = rl.LoadTextureFromImage(charred_img)
	}


	// load grass 

	if grass_data, ok := read_entire_file("assets/Grass.png", context.temp_allocator); ok {
		grass_img := rl.LoadImageFromMemory(".png", raw_data(grass_data), c.int(len(grass_data)))

		sprite_assets.grass = rl.LoadTextureFromImage(grass_img)
	}

	// load player 

	if deer_data, ok := read_entire_file("assets/deer_idle.png", context.temp_allocator); ok {

		deer_img := rl.LoadImageFromMemory(".png", raw_data(deer_data), c.int(len(deer_data)))
		sprite_assets.deer = rl.LoadTextureFromImage(deer_img)
	}

	if ripple_data, ok := read_entire_file("assets/round_cat.png", context.temp_allocator); ok {
		ripple_img := rl.LoadImageFromMemory(
			".png",
			raw_data(ripple_data),
			c.int(len(ripple_data)),
		)
		ripple_texture = rl.LoadTextureFromImage(ripple_img)
	}


	// load fire frames
	for i in 0 ..< 8 {
		filename := fmt.tprintf("assets/Fire 4_2-%d.png", i + 1)
		if fire_data, ok := read_entire_file(filename, context.temp_allocator); ok {
			fire_img := rl.LoadImageFromMemory(".png", raw_data(fire_data), c.int(len(fire_data)))
			sprite_assets.fire[i] = rl.LoadTextureFromImage(fire_img)
			rl.UnloadImage(fire_img)
		} else {
			fmt.println("Failed to load fire animation frame:", filename)
		}
	}

}

unload_all_sprites :: proc() {
	for i in 0 ..< 8 {
		rl.UnloadTexture(sprite_assets.fire[i])
	}
}

get_fire_texture :: proc() -> rl.Texture {
	return sprite_assets.fire[fire_animation_frame]
}

update_animations :: proc() {
	delta_time := rl.GetFrameTime()

	// Update fire animation
	fire_animation_timer += delta_time
	if fire_animation_timer >= fire_animation_speed {
		fire_animation_timer -= fire_animation_speed
		fire_animation_frame = (fire_animation_frame + 1) % 8
	}
}

// Draw the title screen
draw_title_screen :: proc() {
	// Draw background
	rl.ClearBackground({0, 100, 50, 255}) // Dark green background

	// Draw game title
	title_text := "Environmental Engineer"
	rl.DrawText(
		strings.clone_to_cstring(title_text),
		screen_width / 2 - (rl.MeasureText(strings.clone_to_cstring(title_text), 80) / 2),
		screen_height / 2 - 250,
		80,
		rl.WHITE,
	)

	// Draw subtitle
	subtitle_text := "A Survival Journey"
	rl.DrawText(
		strings.clone_to_cstring(subtitle_text),
		screen_width / 2 - (rl.MeasureText(strings.clone_to_cstring(subtitle_text), 40) / 2),
		screen_height / 2 - 100,
		40,
		rl.WHITE,
	)

	// Draw start button
	button_width := 200
	button_height := 60
	button_x := screen_width / 2 - i32(button_width / 2)
	button_y := screen_height / 2

	button_rect := rl.Rectangle {
		x      = f32(button_x),
		y      = f32(button_y),
		width  = f32(button_width),
		height = f32(button_height),
	}

	// Draw button background
	button_color := rl.DARKGREEN
	if rl.CheckCollisionPointRec(mouse_pos, button_rect) {
		button_color = rl.GREEN // Highlight on hover

		// Check if button is clicked
		if rl.IsMouseButtonPressed(.LEFT) {
			current_game_state = .Instructions_Screen
		}
	}

	rl.DrawRectangleRec(button_rect, button_color)
	rl.DrawRectangleLinesEx(button_rect, 2.0, rl.WHITE)

	// Draw button text
	start_text := "START"
	rl.DrawText(
		strings.clone_to_cstring(start_text),
		i32(button_x) + rl.MeasureText(strings.clone_to_cstring(start_text), 30) / 2,
		i32(button_y + 15),
		30,
		rl.WHITE,
	)

	draw_tutorial_button()

	// Draw credits
	credits_text := "Created for Odin Jam 2025"
	rl.DrawText(
		strings.clone_to_cstring(credits_text),
		640 + rl.MeasureText(strings.clone_to_cstring(credits_text), 20) / 2,
		650,
		20,
		rl.WHITE,
	)
}

// Draw the instructions screen
draw_instructions_screen :: proc() {
	// Draw background
	rl.ClearBackground({0, 100, 50, 255}) // Dark green background

	// Draw title
	title_text := "HOW TO PLAY"
	rl.DrawText(
		strings.clone_to_cstring(title_text),
		screen_width / 2 - rl.MeasureText(strings.clone_to_cstring(title_text), 60) / 2,
		50,
		60,
		rl.WHITE,
	)

	// Draw instruction texts
	instructions := []string {
		"1. Build a path from the starting point to the end goal",
		"2. Use your limited supply of path tiles wisely",
		"3. Avoid placing paths near predators or fire",
		"4. Fire will spread each turn, so plan ahead",
		"5. Press SPACE to start the deer's journey once your path is complete",
		"6. Press R to reset the level if needed",
	}

	y_pos := 150
	for instruction in instructions {
		text_color := instruction == instructions[2] ? rl.YELLOW : rl.WHITE // Highlight the important rule
		font_size := instruction == instructions[2] ? 25 : 24 // Make important rule slightly bigger

		rl.DrawText(
			strings.clone_to_cstring(instruction),
			screen_width / 2 - 250,
			i32(y_pos),
			i32(font_size),
			text_color,
		)

		y_pos += 50
	}


	// Draw start button
	button_width: i32 = 300
	button_height: i32 = 60
	button_x: i32 = screen_width / 2 - button_width / 2
	button_y: i32 = 550

	button_rect := rl.Rectangle {
		x      = f32(button_x),
		y      = f32(button_y),
		width  = f32(button_width),
		height = f32(button_height),
	}

	// Draw button background
	button_color := rl.DARKGREEN
	if rl.CheckCollisionPointRec(mouse_pos, button_rect) {
		button_color = rl.GREEN // Highlight on hover

		// Check if button is clicked
		if rl.IsMouseButtonPressed(.LEFT) {
			current_game_state = .Gameplay
			init_game_state()
			init_player()
			init_path_tiles()
		}
	}

	rl.DrawRectangleRec(button_rect, button_color)
	rl.DrawRectangleLinesEx(button_rect, 2.0, rl.WHITE)

	// Draw button text
	start_text := "START GAME"
	rl.DrawText(
		strings.clone_to_cstring(start_text),
		button_x + (button_width - rl.MeasureText(strings.clone_to_cstring(start_text), 30)) / 2,
		i32(button_y + 15),
		30,
		rl.WHITE,
	)
}


// Initialize the game state
init_game_state :: proc() {
	current_turn = 0
	game_over = false
	game_over_reason = ""
	player_won = false

}


// Start the next movement
start_next_move :: proc() {
	// Save the starting position
	previous_position = player_position
	move_in_progress = true

	move_progress = 0.0
}


init_path_tiles :: proc() {
	placed_path_tiles = make([dynamic]PathTile)
	is_path_valid = false
}

is_position_in_path :: proc(row, col: int) -> bool {
	for tile in placed_path_tiles {
		if tile.row == row && tile.col == col {
			return true
		}
	}
	return false
}

find_path_tile_index :: proc(row, col: int) -> int {
	for i in 0 ..< len(placed_path_tiles) {
		if placed_path_tiles[i].row == row && placed_path_tiles[i].col == col {
			return i
		}
	}
	return -1
}

is_adjacent :: proc(row1, col1, row2, col2: int) -> bool {
	// Check horizontal and vertical adjacency (not diagonal)
	row_diff := abs(row1 - row2)
	col_diff := abs(col1 - col2)

	// Adjacent if exactly one coordinate differs by 1 and the other is the same
	return (row_diff == 1 && col_diff == 0) || (row_diff == 0 && col_diff == 1)
}

is_path_continuous_and_reaches_end :: proc(start_row, start_col, end_row, end_col: int) -> bool {
	// Track visited tiles
	visited: [10][10]bool

	// Initialize queue for BFS
	q: queue.Queue(PathTile)
	queue.init(&q)

	// Start from first path tile adjacent to start position
	for tile in placed_path_tiles {
		if is_adjacent(tile.row, tile.col, start_row, start_col) {
			queue.push(&q, tile)
			visited[tile.row][tile.col] = true
			break
		}
	}

	if queue.len(q) == 0 {
		queue.destroy(&q)
		return false // No path tile adjacent to start
	}

	// BFS to traverse the path
	for queue.len(q) > 0 {
		current := queue.pop_front(&q)

		// Check if we've reached the end
		if is_adjacent(current.row, current.col, end_row, end_col) {
			queue.destroy(&q)
			return true
		}

		// Check all adjacent path tiles
		directions := [][2]int{{0, 1}, {1, 0}, {0, -1}, {-1, 0}} // right, down, left, up

		for dir in directions {
			next_row := current.row + dir[0]
			next_col := current.col + dir[1]

			// Check bounds
			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}

			// If it's a path tile and not visited yet
			if level[current_level].grid[next_row][next_col] == .Path &&
			   !visited[next_row][next_col] {
				visited[next_row][next_col] = true
				queue.push(&q, PathTile{row = next_row, col = next_col})
			}
		}
	}

	queue.destroy(&q)
	return false // End not reachable through continuous path
}


validate_path :: proc() {
	if len(placed_path_tiles) == 0 {
		is_path_valid = false
		return
	}

	// Get start and end positions
	start_row := int(level[current_level].start_position.y / TILE_SIZE)
	start_col := int(level[current_level].start_position.x / TILE_SIZE)
	end_row := int(level[current_level].end_position.y)
	end_col := int(level[current_level].end_position.x)

	// Check if the path connects to the start position
	start_connected := false
	for tile in placed_path_tiles {
		// Check if any path tile is adjacent to start
		if is_adjacent(tile.row, tile.col, start_row, start_col) {
			start_connected = true
			break
		}
	}

	if !start_connected {
		is_path_valid = false
		return
	}

	// Use BFS to check if the path is continuous and reaches the end
	is_path_valid = is_path_continuous_and_reaches_end(start_row, start_col, end_row, end_col)
}
// Add this procedure to initialize the player position
init_player :: proc() {
	// Start at the level's start position
	player_position = level[current_level].start_position
	player_position.x = player_position.x * TILE_SIZE + offset_x // Adjust for grid rendering offset
	player_position.y = player_position.y * TILE_SIZE - offset_y

	// Initially, target position is the same as player position
	target_position = player_position

	current_path_index = 0
	is_animating = false
	animation_done = false
}


start_animation :: proc() {
	if is_path_valid && !is_animating && !animation_done {
		start_row := int(level[current_level].start_position.y / TILE_SIZE)
		start_col := int(level[current_level].start_position.x / TILE_SIZE)
		end_row := int(level[current_level].end_position.y)
		end_col := int(level[current_level].end_position.x)

		movement_path = find_path_bfs(start_row, start_col, end_row, end_col)

		if len(movement_path) > 0 {
			is_animating = true
			current_path_index = 0

			// Set initial target
			target_position.x = f32(movement_path[0].col * TILE_SIZE + int(offset_x))
			target_position.y = f32(movement_path[0].row * TILE_SIZE - int(offset_y))
		}
	}
} // Reset the animation to allow replaying
reset_animation :: proc() {
	init_player()
}

// Function to check if we've reached the target position
reached_target :: proc() -> bool {
	// Calculate distance between current position and target
	dx := player_position.x - target_position.x
	dy := player_position.y - target_position.y
	distance := rl.Vector2Length(rl.Vector2{dx, dy})

	// If we're close enough to the target, consider it reached
	return distance < 2.0
}

// Get the next target position in the path
get_next_target :: proc() -> bool {
	if current_path_index < len(movement_path) {
		// Move to the next path tile in the optimal path
		target_position.x = f32(movement_path[current_path_index].col * TILE_SIZE + int(offset_x))
		target_position.y = f32(movement_path[current_path_index].row * TILE_SIZE - int(offset_y))
		current_path_index += 1
		return true
	} else {
		// No more path tiles, move to the end position
		target_position.x = f32(level[current_level].end_position.x * TILE_SIZE + offset_x)
		target_position.y = f32(level[current_level].end_position.y * TILE_SIZE - offset_y)
		return false
	}
}


animate_player :: proc() {
	if !is_animating || game_over {
		return
	}

	delta_time := rl.GetFrameTime()

	// If a move is in progress, animate the movement
	if move_in_progress {
		move_progress += delta_time * 2.0 // Control movement speed here

		if move_progress >= 1.0 {
			// Move complete
			move_progress = 1.0
			move_in_progress = false
			player_position = target_position

			// Start the delay timer
			turn_delay_timer = 0
		} else {
			// Interpolate position for smooth movement
			start_pos := rl.Vector2{previous_position.x, previous_position.y}
			end_pos := rl.Vector2{target_position.x, target_position.y}

			// Use easing function for smoother movement
			t := ease_out_cubic(move_progress)
			player_position = linalg.lerp(start_pos, end_pos, t)
		}
	} else if reached_target() {
		// We're at the target, wait for delay before next move
		turn_delay_timer += delta_time

		if turn_delay_timer >= turn_delay_duration {
			// Process turn events after delay
			process_turn_end()

			// Check for game over conditions after turn processing
			if game_over {
				return
			}

			has_more_targets := get_next_target()

			// If we've reached the end position and there are no more targets
			if !has_more_targets && reached_target() {
				is_animating = false
				animation_done = true
				player_won = true
				game_over = true
				game_over_reason = "You've successfully reached the end!"
				fmt.println("Player won! Level complete!")
			} else {
				// Start the next movement
				start_next_move()
			}
		}
	} else {
		// Start movement to target
		start_next_move()
	}

	// Draw the player at its current position
	draw_player()
}


// Draw the player character
draw_player :: proc() {
	source := rl.Rectangle {
		x      = 0,
		y      = 0,
		width  = -f32(sprite_assets.deer.width),
		height = f32(sprite_assets.deer.height),
	}

	dest := rl.Rectangle {
		x      = player_position.x + TILE_SIZE / 2 - 32,
		y      = player_position.y + TILE_SIZE / 2 - 32,
		height = f32(sprite_assets.deer.height * 2),
		width  = f32(sprite_assets.deer.width * 2),
	}
	rl.DrawTexturePro(sprite_assets.deer, source, dest, {0, 0}, 0, rl.WHITE)
}

handle_animation_controls :: proc() {
	// Start animation with Space key
	if rl.IsKeyPressed(.SPACE) {
		start_animation()
	}

	// Reset animation with R key
	if rl.IsKeyPressed(.R) {
		reset_animation()
	}

}


highlight_path :: proc() {
	// Update shader time uniform
	shader_time := f32(rl.GetTime())
	rl.SetShaderValue(shaders.path_flow, shaders.path_flow_time_loc, &shader_time, .FLOAT)

	// Begin shader mode for path tiles
	// rl.BeginShaderMode(shaders.path_flow)

	for tile in placed_path_tiles {
		x := tile.col * TILE_SIZE + int(offset_x)
		y := tile.row * TILE_SIZE - int(offset_y)

		// Draw path tile with shader
		rl.DrawRectangle(i32(x), i32(y), TILE_SIZE, TILE_SIZE, rl.GREEN)
	}

	//rl.EndShaderMode()

	// Draw outlines without shader
	for tile in placed_path_tiles {
		x := tile.col * TILE_SIZE + int(offset_x)
		y := tile.row * TILE_SIZE - int(offset_y)
		rl.DrawRectangleLines(i32(x), i32(y), TILE_SIZE, TILE_SIZE, rl.DARKGREEN)
	}
}
// Helper function for absolute value
abs :: proc(x: int) -> int {
	return x >= 0 ? x : -x
}

get_level :: proc(level_number: int) -> Level {
	if level_number <= 0 && level_number > LEVEL_COUNT {
		return {}
	}
	current_level = level_number
	level = [LEVEL_COUNT]Level {
		//level 1 
		{
			grid = [10][10]TileType {
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {0, 0},
			end_position = {9, 7},
			available_resources = {
				path_tiles = 15,
				dirt_tiles = 5,
				hunting_ground = 0,
				bridge_tiles = 0,
			},
			level_name = "Tutorial Level",
			level_number = 0,
		},
		{
			grid = [10][10]TileType {
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {0, 0},
			end_position = {0, 5},
			available_resources = {
				path_tiles = 8,
				dirt_tiles = 0,
				hunting_ground = 0,
				bridge_tiles = 0,
			},
			level_name = "Starting Off",
			level_number = 1,
		},
		{
			grid = [10][10]TileType {
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {0, 0},
			end_position = {9, 9},
			available_resources = {
				path_tiles = 20,
				dirt_tiles = 0,
				hunting_ground = 0,
				bridge_tiles = 0,
			},
			level_name = "Hug the Corners!",
			level_number = 2,
		},
		{
			grid = [10][10]TileType {
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {0, 0},
			end_position = {2, 5},
			available_resources = {
				path_tiles = 10,
				dirt_tiles = 5,
				hunting_ground = 0,
				bridge_tiles = 0,
			},
			level_name = "Dirt is your Friend",
			level_number = 2,
		},
	}
	level_grid_copy = level[level_number]
	return level[level_number]
}


draw_level :: proc(level: Level, tile_size: int) {

	for row in 0 ..< 10 {
		for col in 0 ..< 10 {
			// Calculate screen position
			x := col * tile_size
			y := row * tile_size

			// Get the current tile type
			tile := level.grid[row][col]

			// Draw the appropriate sprite/color based on tile type
			rect := rl.Rectangle {
				x      = f32(x) + f32(offset_x),
				y      = f32(y) - offset_y,
				width  = f32(tile_size),
				height = f32(tile_size),
			}

			// Choose color based on tile type
			color := rl.WHITE // Default

			#partial switch tile {
			case .Dirt:
				rl.DrawTextureEx(sprite_assets.dirt, {rect.x, rect.y}, 0, 2, rl.WHITE)
			case .Grass:
				// color = rl.DARKGREEN
				//rl.DrawRectangleRec(rect, color)
				rl.DrawTextureEx(sprite_assets.grass, {rect.x, rect.y}, 0, 2, rl.WHITE)
			// Add some texture for grass

			case .Meadow:
				color = rl.GREEN
				rl.DrawRectangleRec(rect, color)
			// Add flowers for meadow

			case .Predator:
				color = rl.RED
				rl.DrawRectangleRec(rect, color)
				// Add predator icon
				rl.DrawText(
					strings.clone_to_cstring("🐺"),
					i32(rect.x) + 35,
					i32(rect.y) + 30,
					40,
					rl.BLACK,
				)
			case .Path:
				// Path tiles with direction indicators
				rl.DrawRectangleRec(rect, rl.GREEN)
			case .Fire:
				shader_time := f32(rl.GetTime())
				rl.SetShaderValue(
					shaders.fire_distortion,
					shaders.fire_time_loc,
					&shader_time,
					.FLOAT,
				)
				rl.SetShaderValueTexture(
					shaders.fire_distortion,
					shaders.texture0_loc,
					get_fire_texture(),
				)
				rl.DrawTextureEx(sprite_assets.charred_ground, {rect.x, rect.y}, 0, 2, rl.WHITE)
				rl.BeginShaderMode(shaders.fire_distortion)
				rl.DrawTextureEx(get_fire_texture(), {rect.x, rect.y}, 0, 1.25, rl.WHITE)
				rl.EndShaderMode()

			}


			// Draw grid lines
			rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)


			// draw start texture 

			rl.DrawTextureEx(
				sprite_assets.start,
				{
					level.start_position.x * TILE_SIZE + offset_x,
					level.start_position.y * TILE_SIZE - offset_y,
				},
				0,
				2,
				rl.WHITE,
			)
			// draw the exit tile 
			frame_counter += 1
			if frame_counter >= frame_delay {
				frame_counter = 0
				current_gif_frame = (current_gif_frame + 1) % end_gif_frames
			}

			source := rl.Rectangle {
				x      = f32(current_gif_frame * (sprite_assets.end.width / end_gif_frames)),
				y      = 0,
				width  = f32(sprite_assets.end.width / end_gif_frames),
				height = f32(sprite_assets.end.height),
			}

			dest := rl.Rectangle {
				x      = level.end_position.x * TILE_SIZE + f32(offset_x),
				y      = level.end_position.y * TILE_SIZE - offset_y,
				width  = f32(TILE_SIZE),
				height = f32(TILE_SIZE),
			}

			// Draw the current frame
			rl.DrawTexturePro(sprite_assets.end, source, dest, {0, 0}, 0, rl.WHITE)


		}
	}
}


place_tile :: proc() {

	start_row := int(level[current_level].start_position.y)
	start_col := int(level[current_level].start_position.x)
	end_row := int(level[current_level].end_position.y)
	end_col := int(level[current_level].end_position.x)

	if is_animating || game_over {
		return
	}

	for row in 0 ..< 10 {
		for col in 0 ..< 10 {
			x := col * TILE_SIZE
			y := row * TILE_SIZE

			is_start := (row == start_row && col == start_col)
			is_end := (row == end_row && col == end_col)

			rect := rl.Rectangle {
				x      = f32(x) + offset_x,
				y      = f32(y) - offset_y,
				width  = f32(TILE_SIZE),
				height = f32(TILE_SIZE),
			}
			if rl.CheckCollisionPointRec(mouse_pos, rect) {
				if selected_tile != nil {
					if level[current_level].grid[row][col] != .Fire &&
					   level[current_level].grid[row][col] != .Predator &&
					   !is_start &&
					   !is_end {
						// Draw semi-transparent overlay
						rl.DrawRectangleRec(rect, {0, 255, 0, 64})
						rl.DrawRectangleLinesEx(rect, 3, rl.GREEN)
					} else {
						// Show invalid placement indicator
						rl.DrawRectangleRec(rect, {255, 0, 0, 64})
						rl.DrawRectangleLinesEx(rect, 3, rl.RED)
					}
					if rl.IsMouseButtonPressed(.LEFT) {

						// TODO: Add different tiles that can be placed such as dirt etc. 
						#partial switch selected_tile {
						case .Path:
							if level[current_level].available_resources.path_tiles > 0 {

								if !is_position_in_path(row, col) {
									path_tile := PathTile {
										row = row,
										col = col,
									}
									if level[current_level].grid[row][col] != .Fire &&
									   level[current_level].grid[row][col] != .Predator &&
									   !is_start &&
									   !is_end {

										append(&placed_path_tiles, path_tile)
										level[current_level].available_resources.path_tiles -= 1
										level[current_level].grid[row][col] = selected_tile

										trigger_tile_placement_effect(
											i32(x + int(offset_x)),
											i32(y - int(offset_y)),
										)
									}

								}
							}
						case .Dirt:
							if level[current_level].available_resources.dirt_tiles > 0 {

								if level[current_level].grid[row][col] != .Fire &&
								   level[current_level].grid[row][col] != .Predator &&
								   !is_start &&
								   !is_end {
									level[current_level].available_resources.dirt_tiles -= 1
									level[current_level].grid[row][col] = selected_tile
								}
							}
							break

						}


					}
				}
				validate_path()

				if rl.IsMouseButtonPressed(.RIGHT) {
					tile_type := level[current_level].grid[row][col]
					if tile_type == .Path {
						idx := find_path_tile_index(row, col)
						if idx >= 0 {
							ordered_remove(&placed_path_tiles, idx)
							level[current_level].available_resources.path_tiles += 1

							level[current_level].grid[row][col] = level_grid_copy.grid[row][col]
							validate_path()
						}
					}
				}
			}
		}

	}

}


draw_side_bar :: proc() {
	width: i32 = 200 // Slightly wider for more info
	height: i32 = screen_height // Match window height

	rl.DrawRectangleGradientV(0, 0, width, height, rl.LIGHTGRAY, {220, 220, 220, 255})
	rl.DrawRectangleLinesEx({0, 0, f32(width), f32(height)}, 2, rl.DARKGRAY)

	title_text := "CONTROLS"
	rl.DrawText(
		strings.clone_to_cstring(title_text),
		width / 2 - rl.MeasureText(strings.clone_to_cstring(title_text), 24) / 2,
		20,
		24,
		rl.DARKGREEN,
	)

	// Separator line
	rl.DrawLine(20, 55, width - 20, 55, rl.DARKGRAY)

	// === RESOURCES SECTION ===
	rl.DrawText(strings.clone_to_cstring("RESOURCES:"), 20, 70, 18, rl.DARKBLUE)

	// Draw available path tiles
	path_text := fmt.tprintf("Path Tiles: %d", level[current_level].available_resources.path_tiles)
	rl.DrawText(strings.clone_to_cstring(path_text), 30, 100, 16, rl.BLACK)

	// Visual indicators for resources
	resources_y := i32(130)
	#partial switch selected_tile {
	case .Path:
		for i in 0 ..< level[current_level].available_resources.path_tiles {
			if i >= 10 { 	// Show max 10 indicators to avoid clutter
				break
			}
			x_pos := 30 + (i % 5) * 30
			y_pos := resources_y + (i / 5) * 30
			rl.DrawRectangle(x_pos, y_pos, 20, 20, rl.GREEN)
			rl.DrawRectangleLines(x_pos, y_pos, 20, 20, rl.DARKGREEN)
		}

	case .Dirt:
		for i in 0 ..< level[current_level].available_resources.dirt_tiles {
			if i >= 10 { 	// Show max 10 indicators to avoid clutter
				break
			}
			x_pos := 30 + (i % 5) * 30
			y_pos := resources_y + (i / 5) * 30
			rl.DrawRectangle(x_pos, y_pos, 20, 20, rl.BROWN)
			rl.DrawRectangleLines(x_pos, y_pos, 20, 20, rl.YELLOW)
		}
	}
	rl.DrawText(strings.clone_to_cstring("SELECT TILE:"), 20, 200, 18, rl.DARKBLUE)

	grass := rl.Rectangle{50, 230, 50, 50}

	if selected_tile == .Path {
		rl.DrawRectangleRec(grass, rl.GREEN)
		rl.DrawRectangleLinesEx(grass, 3, rl.GOLD) // Highlight with gold border
	} else {
		rl.DrawRectangleRec(grass, rl.DARKGREEN)
		rl.DrawRectangleLinesEx(grass, 1, rl.BLACK)
	}

	rl.DrawText(strings.clone_to_cstring("Path"), 115, 245, 16, rl.BLACK)

	//
	dirt := rl.Rectangle{50, 330, 50, 50}

	if selected_tile == .Dirt {
		rl.DrawRectangleRec(dirt, rl.BROWN)
		rl.DrawRectangleLinesEx(dirt, 3, rl.GOLD)
	} else {

		rl.DrawRectangleRec(dirt, rl.BROWN)
		rl.DrawRectangleLinesEx(grass, 1, rl.BLACK)
	}

	// Check for clicks on the tile selection
	if rl.CheckCollisionPointRec(mouse_pos, grass) && rl.IsMouseButtonPressed(.LEFT) {
		selected_tile = .Path
	}

	if rl.CheckCollisionPointRec(mouse_pos, dirt) && rl.IsMouseButtonPressed(.LEFT) {
		selected_tile = .Dirt
	}


	// === INSTRUCTIONS SECTION ===
	rl.DrawText(strings.clone_to_cstring("HELP:"), 20, 420, 18, rl.DARKBLUE)

	instructions := []string {
		"LEFT CLICK: Place tile",
		"RIGHT CLICK: Remove tile",
		"SPACE: Start simulation",
		"R: Reset level",
		"ESC: Cancel selection",
	}

	for instruction, idx in instructions {
		rl.DrawText(
			strings.clone_to_cstring(instruction),
			30,
			450 + i32(idx * 30),
			14,
			rl.DARKGRAY,
		)
	}

	// === CURRENTLY SELECTED INDICATOR ===
	if selected_tile != nil {
		selected_text := "Currently selected:"
		rl.DrawText(strings.clone_to_cstring(selected_text), 20, 620, 16, rl.BLACK)

		// Draw the selected tile preview
		preview_rect := rl.Rectangle{f32(width / 2 - 25), 650, 50, 50}
		#partial switch selected_tile {
		case .Path:
			rl.DrawRectangleRec(preview_rect, rl.GREEN)
			rl.DrawText(strings.clone_to_cstring("Path"), width / 2 - 20, 610, 16, rl.BLACK)
		case .Dirt:
			rl.DrawRectangleRec(preview_rect, rl.BROWN)
			rl.DrawText(strings.clone_to_cstring("Dirt"), width / 2 - 20, 610, 16, rl.BLACK)
		case .HuntZone:
			rl.DrawRectangleRec(preview_rect, rl.BLUE)
			rl.DrawText(strings.clone_to_cstring("Hunt"), width / 2 - 20, 610, 16, rl.BLACK)
		case .Bridge:
			rl.DrawRectangleRec(preview_rect, rl.BEIGE)
			rl.DrawText(strings.clone_to_cstring("Bridge"), width / 2 - 25, 610, 16, rl.BLACK)
		}

		// Draw cursor indicator when hovering over the grid
		if mouse_pos.x > 250 {
			rl.DrawRectangle(
				i32(mouse_pos.x - 25),
				i32(mouse_pos.y - 25),
				50,
				50,
				{0, 255, 0, 128}, // Semi-transparent green
			)
		}
	}

	if is_path_valid {
		rl.DrawText(strings.clone_to_cstring("Path is VALID"), 20, height - 260, 20, rl.GREEN)
		rl.DrawText(
			strings.clone_to_cstring("Press SPACE to start"),
			20,
			height - 335,
			16,
			rl.DARKGREEN,
		)
	} else {
		rl.DrawText(strings.clone_to_cstring("Path is INVALID"), 20, height - 260, 20, rl.RED)
		rl.DrawText(
			strings.clone_to_cstring("Connect to start & end!"),
			20,
			height - 35,
			16,
			rl.MAROON,
		)
	}
}
check_adjacent_dangers :: proc() {
	// Convert player position to grid coordinates
	player_row := int((player_position.y + offset_y) / TILE_SIZE)
	player_col := int((player_position.x - offset_x) / TILE_SIZE)

	// Check all adjacent tiles (including diagonals)
	directions := [][2]int {
		{0, 1},
		{1, 0},
		{0, -1},
		{-1, 0}, // Orthogonal
		{1, 1},
		{1, -1},
		{-1, 1},
		{-1, -1}, // Diagonal
	}

	for dir in directions {
		next_row := player_row + dir[0]
		next_col := player_col + dir[1]

		if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
			continue
		}

		tile := level[current_level].grid[next_row][next_col]

		#partial switch tile {
		case .Fire:
			game_over = true
			game_over_reason = "You were burned by fire!"
			return

		case .Predator:
			game_over = true
			game_over_reason = "You were caught by a predator!"
			return
		}
	}
}

spread_fire :: proc() {
	fire_tiles: [dynamic]PathTile

	for row in 0 ..< 10 {
		for col in 0 ..< 10 {
			if level[current_level].grid[row][col] == .Fire {
				append(&fire_tiles, PathTile{row = row, col = col})
			}
		}
	}

	new_fire_tiles: [dynamic]PathTile

	for fire in fire_tiles {
		directions := [][2]int{{0, 1}, {1, 0}, {0, -1}, {-1, 0}}

		for dir in directions {
			next_row := fire.row + dir[0]
			next_col := fire.col + dir[1]

			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}

			tile := level[current_level].grid[next_row][next_col]

			if (tile == .Grass || tile == .Meadow) && rand.float32() < fire_spread_chance {
				append(&new_fire_tiles, PathTile{row = next_row, col = next_col})
			}
		}
	}

	for new_fire in new_fire_tiles {
		level[current_level].grid[new_fire.row][new_fire.col] = .Fire
	}

	delete(fire_tiles)
	delete(new_fire_tiles)
}

ease_out_cubic :: proc(t: f32) -> f32 {
	return 1 - math.pow(1 - t, 3)
}


draw_game_status :: proc() {
	if game_over {
		bg_color := player_won ? rl.GREEN : rl.RED
		text_color := rl.WHITE

		rl.DrawRectangle(300, 250, 680, 220, {bg_color.r, bg_color.g, bg_color.b, 200})

		status_text := player_won ? "LEVEL COMPLETE!" : "GAME OVER"
		rl.DrawText(strings.clone_to_cstring(status_text), 420, 280, 40, text_color)

		rl.DrawText(strings.clone_to_cstring(game_over_reason), 340, 340, 30, text_color)

		rl.DrawText(strings.clone_to_cstring("Press 'R' to restart"), 440, 400, 20, text_color)
	} else if is_animating {
		turn_text := fmt.tprintf("TURN %d", current_turn)
		rl.DrawText(strings.clone_to_cstring(turn_text), 550, 50, 40, rl.WHITE)
	}
}


process_turn_end :: proc() {
	current_turn += 1

	// Check for adjacent danger tiles
	check_adjacent_dangers()

	// If game is already over, don't process further
	if game_over {
		return
	}

	// Spread fire
	spread_fire()
}

reset_level :: proc() {
	level = level_grid_copy

}

init_camera :: proc() {
	camera.zoom = 1.2
	camera.target = {0, 0}
	camera.rotation = 0
}

draw_end_screen :: proc() {
	rl.ClearBackground(rl.BLACK)

	rl.DrawText(
		"Congrats you completed the game! The deer made it to safety",
		450,
		500,
		30,
		rl.WHITE,
	)

	rl.DrawText("Press R to restart or ESC to return to the title screen", 450, 700, 25, rl.WHITE)

	if rl.IsKeyPressed(.R) {
		current_level = 0
		reset_level()
		get_level(0)
		init_player()
		init_game_state()
		clear_dynamic_array(&placed_path_tiles)
		current_game_state = .Gameplay
	}

	if rl.IsKeyPressed(.ESCAPE) {
		current_game_state = .Title_Screen
		reset_level()
		get_level(0)
		init_player()
		init_game_state()
		clear_dynamic_array(&placed_path_tiles)

	}

}

update :: proc() {
	screen_width = rl.GetScreenWidth()
	screen_height = rl.GetScreenHeight()

	current_time := f32(rl.GetTime())
	rl.SetShaderValue(shaders.crt_effect, shaders.crt_time_loc, &current_time, .FLOAT)

	if update_render_target {
		rl.UnloadRenderTexture(target)
		target = rl.LoadRenderTexture(i32(screen_width), i32(screen_height))
		update_render_target = false

		resolution := [2]f32{f32(screen_width), f32(screen_height)}
		rl.SetShaderValue(shaders.crt_effect, shaders.crt_resolution_loc, &resolution, .VEC2)
	}

	rl.BeginTextureMode(target)
	rl.ClearBackground(rl.BLACK)

	screen_mouse_pos := rl.GetMousePosition()

	update_animations()

	#partial switch current_game_state {
	case .Tutorial:
		rl.ClearBackground({0, 100, 50, 255})

		rl.BeginMode2D(camera)
		mouse_pos = rl.GetScreenToWorld2D(screen_mouse_pos, camera)

		if rl.IsKeyPressed(.ESCAPE) || rl.IsMouseButtonPressed(.RIGHT) {
			selected_tile = nil
		}

		draw_level(level[current_level], TILE_SIZE)
		draw_side_bar()

		highlight_path()
		place_tile()
		handle_animation_controls()
		animate_player()

		update_and_draw_tile_effects()
		draw_game_status()

		update_tutorial()
		draw_tutorial()

		if !tutorial.active {
			current_game_state = .Gameplay
		}

		if game_over {
			if rl.IsKeyPressed(.R) {
				init_game_state()
				init_player()
				reset_level()
				clear_dynamic_array(&placed_path_tiles)
				tutorial.current_step = 0
				tutorial.active = true
				for i in 0 ..< len(tutorial.steps) {
					tutorial.steps[i].completed = false
				}
			}
		}
		rl.EndMode2D()
	case .Title_Screen:
		mouse_pos = rl.GetMousePosition()
		draw_title_screen()

	case .Instructions_Screen:
		mouse_pos = rl.GetMousePosition()
		draw_instructions_screen()

	case .Gameplay:
		rl.ClearBackground({0, 120, 153, 255})
		// render_trippy_background()
		rl.BeginMode2D(camera)
		mouse_pos = rl.GetScreenToWorld2D(screen_mouse_pos, camera)

		if rl.IsKeyPressed(.ESCAPE) || rl.IsMouseButtonPressed(.RIGHT) {
			selected_tile = nil
		}

		draw_level(level[current_level], TILE_SIZE)
		draw_side_bar()

		highlight_path()
		place_tile()
		handle_animation_controls()
		animate_player()

		update_and_draw_tile_effects()
		draw_game_status()
		//render_trippy_background()

		if game_over {
			if rl.IsKeyPressed(.R) {
				init_game_state()
				init_player()
				reset_level()
				clear_dynamic_array(&placed_path_tiles)
			}

			if rl.IsKeyPressed(.ESCAPE) {
				current_game_state = .Title_Screen
			}

			if rl.IsKeyPressed(.SPACE) {
				init_game_state()
				init_player()
				reset_level()
				clear_dynamic_array(&placed_path_tiles)
				if current_level + 1 >= LEVEL_COUNT {
					current_game_state = .EndGame
					rl.EndMode2D()
					rl.EndTextureMode()
					return
				}
				get_level(current_level + 1)
			}

			rl.DrawText(
				strings.clone_to_cstring("Press Space to go to the next level"),
				440,
				430,
				20,
				rl.WHITE,
			)
		}
		rl.EndMode2D()

	case .EndGame:
		draw_end_screen()
	}

	rl.EndTextureMode()

	// Now draw the render texture to the screen with the CRT shader
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	// Apply the CRT effect shader when drawing the render texture
	rl.BeginShaderMode(shaders.crt_effect)

	// Draw the render texture flipped (raylib textures are y-flipped)
	rl.DrawTextureRec(
		target.texture,
		{0, 0, f32(target.texture.width), -f32(target.texture.height)},
		{0, 0},
		rl.WHITE,
	)

	rl.EndShaderMode()
	rl.EndDrawing()

	// Anything allocated using temp allocator is invalid after this.
	free_all(context.temp_allocator)
}

render_trippy_background :: proc() {
	// Update shader time uniform
	current_time := f32(rl.GetTime())
	rl.SetShaderValue(shaders.trippy_background, shaders.trippy_time_loc, &current_time, .FLOAT)

	// First, render a simple gradient to the background texture
	rl.BeginTextureMode(background_texture)

	// Draw a gradient or some base pattern for the shader to distort
	rl.DrawRectangleGradientV(
		0,
		0,
		i32(background_texture.texture.width),
		i32(background_texture.texture.height),
		{80, 40, 120, 255}, // Dark purple
		{20, 60, 100, 255},
	) // Dark blue

	rl.EndTextureMode()

	// Then draw the background with the trippy shader
	rl.BeginShaderMode(shaders.trippy_background)

	// Draw the background texture (flipped since raylib textures are y-flipped)
	rl.DrawTextureRec(
		background_texture.texture,
		{0, 0, f32(background_texture.texture.width), -f32(background_texture.texture.height)},
		{0, 0},
		rl.WHITE,
	)

	rl.EndShaderMode()
}


draw_tutorial_button :: proc() {
	// Draw tutorial button below the start button
	tutorial_button_width := 200
	tutorial_button_height := 60
	tutorial_button_x := screen_width / 2 - i32(tutorial_button_width / 2)
	tutorial_button_y := screen_height / 2 + 80 // Position below the start button

	tutorial_button_rect := rl.Rectangle {
		x      = f32(tutorial_button_x),
		y      = f32(tutorial_button_y),
		width  = f32(tutorial_button_width),
		height = f32(tutorial_button_height),
	}

	create_tutorial_level :: proc() -> Level {
		tutorial_level := Level {
			grid = [10][10]TileType {
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {0, 2},
			end_position = {9, 7},
			available_resources = {
				path_tiles = 15,
				dirt_tiles = 5,
				hunting_ground = 0,
				bridge_tiles = 0,
			},
			level_name = "Tutorial Level",
			level_number = 0,
		}

		return tutorial_level
	}

	// Draw button background
	tutorial_button_color := rl.DARKBLUE
	if rl.CheckCollisionPointRec(mouse_pos, tutorial_button_rect) {
		tutorial_button_color = rl.BLUE // Highlight on hover

		// Check if button is clicked
		if rl.IsMouseButtonPressed(.LEFT) {
			// Start the tutorial
			current_game_state = .Tutorial
			current_level = 0
			level_grid_copy = level[0]
			init_game_state()
			init_player()
			init_path_tiles()
			init_tutorial()
		}
	}

	rl.DrawRectangleRec(tutorial_button_rect, tutorial_button_color)
	rl.DrawRectangleLinesEx(tutorial_button_rect, 2.0, rl.WHITE)

	// Draw button text
	tutorial_text := "TUTORIAL"
	rl.DrawText(
		strings.clone_to_cstring(tutorial_text),
		tutorial_button_x + 20,
		tutorial_button_y + 15,
		30,
		rl.WHITE,
	)
}


window_resize_callback :: proc() {
	update_render_target = true
}

// Modify your init procedure to initialize the game state
init :: proc() {
	run = true
	rl.SetTargetFPS(60)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Deer Path - A Survival Journey")
	level = get_level(0)
	init_shaders()
	target = rl.LoadRenderTexture(1280, 720)
	background_texture = rl.LoadRenderTexture(1280, 720)
	init_camera()


	// Initialize game to title screen
	current_game_state = .Title_Screen
	load_sprites()
}


shutdown :: proc() {
	unload_all_sprites()
	unload_shaders()
	rl.CloseWindow()
}

parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
	update_render_target = true // Mark for render target update
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}

	return run
}
