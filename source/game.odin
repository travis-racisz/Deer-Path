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


//SCREEN SIZE THANGS 
scaling_factor: f32 = 1.0
base_tile_size: i32 = 64
min_tile_size: i32 = 32

// AUDIO
audio_init := false
game_music: rl.Music
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
fire_spread_chance: f32 = 0.1 // Chance for fire to spread each turn
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
LEVEL_COUNT :: 6
offset_x := f32(rl.GetScreenWidth() / 2 + TILE_SIZE * 10)
offset_y := f32(rl.GetScreenHeight() / 2 - TILE_SIZE)


// TODO: Figure out why the path only traces from {0,0}


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
	predator:       rl.Texture,
	hunting_ground: rl.Texture,
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
	tutorial.overlay_opacity = 0.0
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
				f32(level[tutorial_level_inx].start_position.x * TILE_SIZE + offset_x - 32),
				f32(level[tutorial_level_inx].start_position.y * TILE_SIZE - offset_y - 32),
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
				f32(level[tutorial_level_inx].end_position.x * TILE_SIZE + offset_x - 32),
				f32(level[tutorial_level_inx].end_position.y * TILE_SIZE - offset_y - 32),
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
			message = "Now click on the grid to place path tiles. Create a path from start to end. Diaganol Path squares are not valid",
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
			message = "This Indicator will tell you if your path is valid or not",
			target_area = {20, 720, 180, 50},
			highlight = true,
			wait_for_input = true,
			input_type = .Any,
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
			message = "Place some Dirt Tiles around the fire to prevent it from spreading",
			target_area = {50, 330, 50, 50},
			highlight = true,
			wait_for_input = true,
			input_type = .Any,
			completed = false,
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
tutorial_level_inx := 1
update_tutorial :: proc() {
	if !tutorial.active || tutorial.current_step >= len(tutorial.steps) {
		return
	}


	if rl.IsKeyPressed(.ESCAPE) {
		current_game_state = .Title_Screen

	}

	// Update pulse effect for highlights
	tutorial.pulse_timer += rl.GetFrameTime()
	// pulse_factor := math.sin_f32(tutorial.pulse_timer * 4.0) * 0.2 + 0.8

	// Get current step
	current := &tutorial.steps[tutorial.current_step]

	// For fire tile tutorial step
	if tutorial.current_step == 7 {
		// Find a fire tile to highlight
		found_fire := false
		for row in 0 ..< 10 {
			for col in 0 ..< 10 {
				if level[tutorial_level_inx].grid[row][col] == .Fire {
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
		if tutorial.current_step == 5 && is_path_valid {
			current.completed = true
			tutorial.current_step += 1
		}
	}
}

draw_tutorial :: proc() {
	if !tutorial.active || tutorial.current_step >= len(tutorial.steps) {
		return
	}

	current := tutorial.steps[tutorial.current_step]


	if current.highlight {
		pulse_amount := math.sin_f32(tutorial.pulse_timer * 4.0) * 10.0
		highlight_rect := current.target_area

		rl.DrawRectangleRec(highlight_rect, {0, 0, 0, 0})

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

	message_width: i32 = 400
	message_height := 100
	message_x := (screen_width / 2) - message_width / 2
	message_y := screen_height - 250

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


	rl.DrawText(
		strings.clone_to_cstring(tutorial.steps[tutorial.current_step].message),
		220,
		30,
		25,
		rl.WHITE,
	)


	if current.wait_for_input {
		prompt_text: string
		#partial switch current.input_type {
		case .Click:
			prompt_text = "Click on the highlighted area to continue"
		case .Key:
			prompt_text = fmt.tprintf("Press %v to continue", current.key)
		case .Any:
			prompt_text = "Press Enter or click to continue"
		}

		rl.DrawText(
			strings.clone_to_cstring(prompt_text),
			message_x +
			message_width / 2 -
			rl.MeasureText(strings.clone_to_cstring(prompt_text), 16) / 2,
			i32(message_y) + i32(message_height - 60),
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
			normalized_time := elapsed / tile_placement_anim.duration


			rl.SetShaderValue(
				shaders.tile_placement,
				shaders.tile_time_loc,
				&normalized_time,
				.FLOAT,
			)


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

	if shaders.tile_placement.id == 0 {
		fmt.println("ERROR: Tile placement shader failed to load")
	}

	shaders.path_flow_time_loc = rl.GetShaderLocation(shaders.path_flow, "time")
	shaders.path_flow_resolution_loc = rl.GetShaderLocation(shaders.path_flow, "resolution")

	time := rl.GetTime()
	rl.SetShaderValue(ripple_shader, rl.GetShaderLocation(ripple_shader, "u_time"), &time, .FLOAT)

	shaders.crt_effect = rl.LoadShader(nil, "assets/shaders/crt_effect.fs")

	shaders.crt_resolution_loc = rl.GetShaderLocation(shaders.crt_effect, "resolution")
	shaders.crt_time_loc = rl.GetShaderLocation(shaders.crt_effect, "time")
	shaders.crt_texture0_loc = rl.GetShaderLocation(shaders.crt_effect, "texture0")

	rl.SetShaderValue(shaders.crt_effect, shaders.crt_resolution_loc, &resolution, .VEC2)
	rl.SetShaderValue(shaders.crt_effect, shaders.crt_texture0_loc, &[1]i32{0}, .INT)

	shaders.fire_time_loc = rl.GetShaderLocation(shaders.fire_distortion, "time")
	shaders.fire_texture0_loc = rl.GetShaderLocation(shaders.fire_distortion, "texture0")

	shaders.tile_time_loc = rl.GetShaderLocation(shaders.tile_placement, "time")
	shaders.tile_pos_loc = rl.GetShaderLocation(shaders.tile_placement, "tilePos")
	shaders.tile_resolution_loc = rl.GetShaderLocation(shaders.tile_placement, "resolution")

	shaders.trippy_background = rl.LoadShader(nil, "assets/shaders/trippy_background.fs")

	shaders.trippy_time_loc = rl.GetShaderLocation(shaders.trippy_background, "time")
	shaders.trippy_resolution_loc = rl.GetShaderLocation(shaders.trippy_background, "resolution")
	shaders.trippy_texture0_loc = rl.GetShaderLocation(shaders.trippy_background, "texture0")

	rl.SetShaderValue(shaders.trippy_background, shaders.trippy_resolution_loc, &resolution, .VEC2)
	rl.SetShaderValue(shaders.trippy_background, shaders.trippy_texture0_loc, &[1]i32{0}, .INT)

	rl.SetShaderValue(shaders.path_flow, shaders.path_flow_resolution_loc, &resolution, .VEC2)
}

unload_shaders :: proc() {
	rl.UnloadShader(shaders.path_flow)
	rl.UnloadShader(shaders.fire_distortion)
	rl.UnloadShader(shaders.tile_placement)
}

find_path_bfs :: proc(start_row, start_col, end_row, end_col: int) -> [dynamic]PathTile {
	result_path := make([dynamic]PathTile)

	fmt.println("Looking for path from", start_row, start_col, "to", end_row, end_col)

	q: queue.Queue(PathTile)
	queue.init(&q)

	visited: [10][10]bool

	parent: [10][10]PathTile

	start := PathTile {
		row = start_row,
		col = start_col,
	}
	queue.push(&q, start)
	visited[start_row][start_col] = true

	found_path := false
	for queue.len(q) > 0 && !found_path {
		current := queue.pop_front(&q)


		if current.row == end_row && current.col == end_col {
			found_path = true
			fmt.println("Found path to end!")

			path_tile := current
			for path_tile.row != start_row || path_tile.col != start_col {
				append(&result_path, path_tile)
				path_tile = parent[path_tile.row][path_tile.col]
			}
			append(&result_path, start)

			for i, j := 0, len(result_path) - 1; i < j; i, j = i + 1, j - 1 {
				result_path[i], result_path[j] = result_path[j], result_path[i]
			}

			break
		}

		directions := [][2]int{{0, 1}, {1, 0}, {0, -1}, {-1, 0}} // right, down, left, up

		for dir in directions {
			next_row := current.row + dir[0]
			next_col := current.col + dir[1]

			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}

			if visited[next_row][next_col] {
				continue
			}

			if level[current_level].grid[next_row][next_col] != .Path &&
			   !(next_row == end_row && next_col == end_col) {
				continue
			}

			next := PathTile {
				row = next_row,
				col = next_col,
			}
			queue.push(&q, next)
			visited[next_row][next_col] = true
			parent[next_row][next_col] = current
		}
	}

	queue.destroy(&q)

	if !found_path {
		fmt.println("WARNING: No path found!")
	} else {
		fmt.println("Path length:", len(result_path))
	}

	return result_path
}

load_sprites :: proc() {

	// load Gun sprite 
	if gun_data, ok := read_entire_file("assets/Gun.png", context.temp_allocator); ok {
		gun_img := rl.LoadImageFromMemory(".png", raw_data(gun_data), c.int(len(gun_data)))

		sprite_assets.hunting_ground = rl.LoadTextureFromImage(gun_img)
	}


	// laod predator sprite 


	if wolf_data, ok := read_entire_file("assets/wolf_black_full.png", context.temp_allocator);
	   ok {
		wolf_img := rl.LoadImageFromMemory(".png", raw_data(wolf_data), c.int(len(wolf_data)))

		sprite_assets.predator = rl.LoadTextureFromImage(wolf_img)
	}

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

	rl.UnloadTexture(sprite_assets.hunting_ground)
	rl.UnloadTexture(sprite_assets.deer)

	rl.UnloadTexture(sprite_assets.grass)
	rl.UnloadTexture(sprite_assets.charred_ground)

	rl.UnloadTexture(sprite_assets.end)

	rl.UnloadTexture(sprite_assets.dirt)

	rl.UnloadTexture(sprite_assets.start)

	rl.UnloadTexture(sprite_assets.predator)
}

get_fire_texture :: proc() -> rl.Texture {
	return sprite_assets.fire[fire_animation_frame]
}

update_animations :: proc() {
	delta_time := rl.GetFrameTime()

	fire_animation_timer += delta_time
	if fire_animation_timer >= fire_animation_speed {
		fire_animation_timer -= fire_animation_speed
		fire_animation_frame = (fire_animation_frame + 1) % 8
	}
}

draw_title_screen :: proc() {
	rl.ClearBackground({0, 100, 50, 255}) // Dark green background

	title_text := "Deer Path"
	rl.DrawText(
		strings.clone_to_cstring(title_text),
		screen_width / 2 - (rl.MeasureText(strings.clone_to_cstring(title_text), 80) / 2),
		screen_height / 2 - 250,
		80,
		rl.WHITE,
	)

	subtitle_text := "A Survival Journey"
	rl.DrawText(
		strings.clone_to_cstring(subtitle_text),
		screen_width / 2 - (rl.MeasureText(strings.clone_to_cstring(subtitle_text), 40) / 2),
		screen_height / 2 - 100,
		40,
		rl.WHITE,
	)

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

	button_color := rl.DARKGREEN
	if rl.CheckCollisionPointRec(mouse_pos, button_rect) {
		button_color = rl.GREEN

		if rl.IsMouseButtonPressed(.LEFT) {
			current_game_state = .Instructions_Screen
		}
	}

	rl.DrawRectangleRec(button_rect, button_color)
	rl.DrawRectangleLinesEx(button_rect, 2.0, rl.WHITE)

	start_text := "START"
	rl.DrawText(
		strings.clone_to_cstring(start_text),
		i32(button_x) + rl.MeasureText(strings.clone_to_cstring(start_text), 30) / 2,
		i32(button_y + 15),
		30,
		rl.WHITE,
	)

	draw_tutorial_button()

	credits_text := "Created for Odin Jam 2025"
	rl.DrawText(
		strings.clone_to_cstring(credits_text),
		640 + rl.MeasureText(strings.clone_to_cstring(credits_text), 20) / 2,
		750,
		20,
		rl.WHITE,
	)
}

draw_instructions_screen :: proc() {
	rl.ClearBackground({0, 100, 50, 255}) // Dark green background

	title_text := "HOW TO PLAY"
	rl.DrawText(
		strings.clone_to_cstring(title_text),
		screen_width / 2 - rl.MeasureText(strings.clone_to_cstring(title_text), 60) / 2,
		50,
		60,
		rl.WHITE,
	)

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

	button_color := rl.DARKGREEN
	if rl.CheckCollisionPointRec(mouse_pos, button_rect) {
		button_color = rl.GREEN // Highlight on hover

		if rl.IsMouseButtonPressed(.LEFT) {
			current_game_state = .Gameplay
			init_game_state()
			init_player()
			init_path_tiles()
		}
	}

	rl.DrawRectangleRec(button_rect, button_color)
	rl.DrawRectangleLinesEx(button_rect, 2.0, rl.WHITE)

	start_text := "START GAME"
	rl.DrawText(
		strings.clone_to_cstring(start_text),
		button_x + (button_width - rl.MeasureText(strings.clone_to_cstring(start_text), 30)) / 2,
		i32(button_y + 15),
		30,
		rl.WHITE,
	)
}


init_game_state :: proc() {
	current_turn = 0
	game_over = false
	game_over_reason = ""
	player_won = false

}


start_next_move :: proc() {
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
	row_diff := abs(row1 - row2)
	col_diff := abs(col1 - col2)

	return (row_diff == 1 && col_diff == 0) || (row_diff == 0 && col_diff == 1)
}

is_path_continuous_and_reaches_end :: proc(start_row, start_col, end_row, end_col: int) -> bool {
	visited: [10][10]bool

	q: queue.Queue(PathTile)
	queue.init(&q)

	for tile in placed_path_tiles {
		if is_adjacent(tile.row, tile.col, start_row, start_col) {
			queue.push(&q, tile)
			visited[tile.row][tile.col] = true
			break
		}
	}

	if queue.len(q) == 0 {
		queue.destroy(&q)
		return false
	}

	for queue.len(q) > 0 {
		current := queue.pop_front(&q)

		if is_adjacent(current.row, current.col, end_row, end_col) {
			queue.destroy(&q)
			return true
		}

		directions := [][2]int{{0, 1}, {1, 0}, {0, -1}, {-1, 0}} // right, down, left, up

		for dir in directions {
			next_row := current.row + dir[0]
			next_col := current.col + dir[1]

			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}


			if level[current_level].grid[next_row][next_col] == .Path &&
			   !visited[next_row][next_col] {
				visited[next_row][next_col] = true
				queue.push(&q, PathTile{row = next_row, col = next_col})
			}
		}
	}

	queue.destroy(&q)
	return false
}


validate_path :: proc() {
	if len(placed_path_tiles) == 0 {
		is_path_valid = false
		return
	}

	start_row := int(level[current_level].start_position.y)
	start_col := int(level[current_level].start_position.x)
	end_row := int(level[current_level].end_position.y)
	end_col := int(level[current_level].end_position.x)

	// Debug
	fmt.println("Validating path with start position:", start_row, start_col)

	start_connected := false
	for tile in placed_path_tiles {
		if is_adjacent(tile.row, tile.col, start_row, start_col) {
			start_connected = true
			break
		}
	}

	if !start_connected {
		is_path_valid = false
		return
	}

	is_path_valid = is_path_continuous_and_reaches_end(start_row, start_col, end_row, end_col)
}

init_player :: proc() {
	player_position = {
		level[current_level].start_position.x * TILE_SIZE + offset_x,
		level[current_level].start_position.y * TILE_SIZE - offset_y,
	}

	target_position = player_position

	current_path_index = 0
	is_animating = false
	animation_done = false
}
start_animation :: proc() {
	if is_path_valid && !is_animating && !animation_done {
		start_row := int(level[current_level].start_position.y)
		start_col := int(level[current_level].start_position.x)
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
}


reset_animation :: proc() {
	init_player()
}

reached_target :: proc() -> bool {
	dx := player_position.x - target_position.x
	dy := player_position.y - target_position.y
	distance := rl.Vector2Length(rl.Vector2{dx, dy})

	return distance < 2.0
}

get_next_target :: proc() -> bool {
	if current_path_index < len(movement_path) {
		target_position.x = f32(movement_path[current_path_index].col * TILE_SIZE + int(offset_x))
		target_position.y = f32(movement_path[current_path_index].row * TILE_SIZE - int(offset_y))
		current_path_index += 1
		return true
	} else {
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

	if move_in_progress {
		move_progress += delta_time * 2.0

		if move_progress >= 1.0 {
			move_progress = 1.0
			move_in_progress = false
			player_position = target_position

			turn_delay_timer = 0
		} else {
			start_pos := rl.Vector2{previous_position.x, previous_position.y}
			end_pos := rl.Vector2{target_position.x, target_position.y}

			t := ease_out_cubic(move_progress)
			player_position = linalg.lerp(start_pos, end_pos, t)
		}
	} else if reached_target() {
		turn_delay_timer += delta_time

		if turn_delay_timer >= turn_delay_duration {
			process_turn_end()

			if game_over {
				return
			}

			has_more_targets := get_next_target()

			if !has_more_targets && reached_target() {
				is_animating = false
				animation_done = true
				player_won = true
				game_over = true
				game_over_reason = "You've successfully reached the end!"
				fmt.println("Player won! Level complete!")
				free(&movement_path)
			} else {
				start_next_move()
			}
		}
	} else {
		start_next_move()
	}

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
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {4, 0},
			end_position = {0, 5},
			available_resources = {
				path_tiles = 8,
				dirt_tiles = 0,
				hunting_ground = 2,
				bridge_tiles = 0,
			},
			level_name = "Starting Off",
			level_number = 0,
		},
		{
			grid = [10][10]TileType {
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
				},
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
				path_tiles = 20,
				dirt_tiles = 6,
				hunting_ground = 1,
				bridge_tiles = 0,
			},
			level_name = "Watch that fire",
			level_number = 1,
		},
		{
			grid = [10][10]TileType {
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
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
				dirt_tiles = 5,
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
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Fire, .Grass, .Grass, .Grass, .Grass},
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
				dirt_tiles = 6,
				hunting_ground = 0,
				bridge_tiles = 0,
			},
			level_name = "Dirt is your Friend",
			level_number = 2,
		},
		{
			grid = [10][10]TileType {
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
				{
					.Grass,
					.Predator,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Predator,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {4, 0},
			end_position = {4, 9},
			available_resources = {
				path_tiles = 16,
				dirt_tiles = 0,
				hunting_ground = 2,
				bridge_tiles = 0,
			},
			level_name = "Send in the hunters",
			level_number = 0,
		},
		{
			grid = [10][10]TileType {
				{.Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Fire},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Grass,
					.Predator,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
					.Predator,
					.Grass,
					.Grass,
				},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
			},
			start_position = {4, 4},
			end_position = {9, 5},
			available_resources = {
				path_tiles = 8,
				dirt_tiles = 3,
				hunting_ground = 2,
				bridge_tiles = 0,
			},
			level_name = "Rock and a hard place",
			level_number = 0,
		},
	}
	level_grid_copy = level[level_number]
	return level[level_number]
}


draw_level :: proc(level: Level, tile_size: int) {
	// Draw level name on screen 
	if current_game_state != .Tutorial {
		rl.DrawText(
			strings.clone_to_cstring(level.level_name),
			screen_width / 2 - rl.MeasureText(strings.clone_to_cstring(level.level_name), 50),
			10,
			50,
			rl.WHITE,
		)
	}


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
				rl.DrawRectangleRec(rect, color)
				rl.DrawTextureEx(sprite_assets.grass, {rect.x, rect.y}, 0, 2, rl.WHITE)
			// Add some texture for grass

			case .HuntZone:
				color = rl.ORANGE
				rl.DrawRectangleRec(rect, color)
				rl.DrawTextureEx(sprite_assets.hunting_ground, {rect.x, rect.y}, 0, 2, rl.WHITE)
			// Add flowers for meadow

			case .Predator:
				color = rl.RED
				rl.DrawRectangleRec(rect, color)
				rl.DrawTextureEx(sprite_assets.predator, {rect.x, rect.y}, 0, 2, rl.WHITE)
			// Add predator icon
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
					if selected_tile == .HuntZone {
						if level[current_level].grid[row][col] != .Fire &&
						   level[current_level].grid[row][col] != .Path &&
						   !is_start &&
						   !is_end {

							rl.DrawRectangleRec(rect, {0, 255, 0, 64})
							rl.DrawRectangleLinesEx(rect, 3, rl.GREEN)
						} else {

							rl.DrawRectangleRec(rect, {255, 0, 0, 64})
							rl.DrawRectangleLinesEx(rect, 3, rl.RED)
						}
					}
					if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonDown(.LEFT) {

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
									   level[current_level].grid[row][col] != .HuntZone &&
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
								   !is_end &&
								   level[current_level].grid[row][col] != .Dirt {
									level[current_level].available_resources.dirt_tiles -= 1
									level[current_level].grid[row][col] = selected_tile
								}
							}
							break

						case .HuntZone:
							if level[current_level].available_resources.hunting_ground > 0 {

								if level[current_level].grid[row][col] != .Fire &&
								   level[current_level].grid[row][col] != .Grass &&
								   !is_start &&
								   !is_end &&
								   level[current_level].grid[row][col] != .HuntZone {
									level[current_level].available_resources.hunting_ground -= 1
									level[current_level].grid[row][col] = selected_tile
								}
							}

						}


					}
				}
				validate_path()

				if rl.IsMouseButtonPressed(.RIGHT) || rl.IsMouseButtonDown(.RIGHT) {
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
					if tile_type == .Dirt {
						level[current_level].available_resources.dirt_tiles += 1

						level[current_level].grid[row][col] = level_grid_copy.grid[row][col]
						validate_path()
					}
					if tile_type == .HuntZone {
						level[current_level].available_resources.hunting_ground += 1

						level[current_level].grid[row][col] = level_grid_copy.grid[row][col]
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
	#partial switch selected_tile {
	case .Path:
		path_text := fmt.tprintf("Tiles: %d", level[current_level].available_resources.path_tiles)
		rl.DrawText(strings.clone_to_cstring(path_text), 30, 100, 16, rl.BLACK)
		break
	case .Dirt:
		path_text := fmt.tprintf("Tiles: %d", level[current_level].available_resources.dirt_tiles)
		rl.DrawText(strings.clone_to_cstring(path_text), 30, 100, 16, rl.BLACK)
		break
	case .HuntZone:
		path_text := fmt.tprintf(
			"Tiles: %d",
			level[current_level].available_resources.hunting_ground,
		)
		rl.DrawText(strings.clone_to_cstring(path_text), 30, 100, 16, rl.BLACK)
		break
	case:
		path_text := fmt.tprintf("Tiles: %d", level[current_level].available_resources.path_tiles)
		rl.DrawText(strings.clone_to_cstring(path_text), 30, 100, 16, rl.BLACK)
		break
	}
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
	case .HuntZone:
		for i in 0 ..< level[current_level].available_resources.hunting_ground {
			if i >= 10 { 	// Show max 10 indicators to avoid clutter
				break
			}
			x_pos := 30 + (i % 5) * 30
			y_pos := resources_y + (i / 5) * 30
			rl.DrawRectangle(x_pos, y_pos, 20, 20, rl.ORANGE)
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
	rl.DrawText(strings.clone_to_cstring("Dirt"), 115, 345, 16, rl.BLACK)
	dirt := rl.Rectangle{50, 330, 50, 50}


	hunt_zone := rl.Rectangle{50, 430, 50, 50}
	rl.DrawText(strings.clone_to_cstring("PREDATOR"), 115, 445, 14, rl.BLACK)
	rl.DrawText(strings.clone_to_cstring("REMOVER"), 115, 459, 14, rl.BLACK)

	if selected_tile == .HuntZone {
		rl.DrawRectangleRec(hunt_zone, rl.ORANGE)
		rl.DrawRectangleLinesEx(dirt, 3, rl.GOLD)
	} else {

		rl.DrawRectangleRec(hunt_zone, rl.ORANGE)
		rl.DrawRectangleLinesEx(grass, 1, rl.BLACK)
	}
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
	if rl.CheckCollisionPointRec(mouse_pos, hunt_zone) && rl.IsMouseButtonPressed(.LEFT) {
		selected_tile = .HuntZone
	}

	// === INSTRUCTIONS SECTION ===
	rl.DrawText(strings.clone_to_cstring("HELP:"), 20, 520, 18, rl.DARKBLUE)

	instructions := []string {
		"LEFT CLICK: Place tile",
		"RIGHT CLICK: Remove tile",
		"SPACE: Start simulation",
		"R: Reset level",
		"ESC: Cancel selection",
	}

	for instruction, idx in instructions {
		rl.DrawText(strings.clone_to_cstring(instruction), 30, 550 + i32(idx * 30), 12, rl.BLACK)
	}


	if is_path_valid {
		rl.DrawText(strings.clone_to_cstring("Path is VALID"), 20, height - 220, 20, rl.GREEN)
		rl.DrawText(
			strings.clone_to_cstring("Press SPACE to start"),
			20,
			height - 200,
			16,
			rl.DARKGREEN,
		)
	} else {
		rl.DrawText(strings.clone_to_cstring("Path is INVALID"), 20, height - 220, 20, rl.RED)
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
		directions := [][2]int {
			{0, 1},
			{1, 0},
			{0, -1},
			{-1, 0},
			{1, 1},
			{-1, 1},
			{1, -1},
			{-1, -1},
		}

		for dir in directions {
			next_row := fire.row + dir[0]
			next_col := fire.col + dir[1]

			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}

			tile := level[current_level].grid[next_row][next_col]

			if (tile == .Grass || tile == .Path) && rand.float32() < fire_spread_chance {
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

		rl.DrawRectangle(400, 250, 680, 220, {bg_color.r, bg_color.g, bg_color.b, 200})

		status_text := player_won ? "LEVEL COMPLETE!" : "GAME OVER"
		rl.DrawText(strings.clone_to_cstring(status_text), 420, 280, 40, text_color)

		rl.DrawText(strings.clone_to_cstring(game_over_reason), 420, 340, 30, text_color)

		rl.DrawText(strings.clone_to_cstring("Press 'R' to restart"), 440, 400, 20, text_color)
	} else if is_animating {
		turn_text := fmt.tprintf("TURN %d", current_turn)
		rl.DrawText(strings.clone_to_cstring(turn_text), 450, 50, 40, rl.WHITE)
	}
}


process_turn_end :: proc() {
	current_turn += 1

	check_adjacent_dangers()

	if game_over {
		return
	}

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

play_audio: bool

initialize_audio :: proc() {
	audio_init = true
	rl.InitAudioDevice()

	game_music = rl.LoadMusicStream("assets/chunky_monkey_shuffle.mp3")


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

	if play_audio {
		if !rl.IsMusicStreamPlaying(game_music) {
			rl.PlayMusicStream(game_music)
		}
		if rl.IsMusicStreamPlaying(game_music) {
			rl.UpdateMusicStream(game_music)
		}
	}

	screen_mouse_pos := rl.GetMousePosition()
	play_audio_rect := rl.Rectangle {
		x      = f32(screen_width / 2 - 100),
		y      = f32(screen_height / 2 + 150),
		width  = 200,
		height = 60,
	}

	button_color := play_audio ? rl.GREEN : rl.DARKGREEN


	update_animations()

	#partial switch current_game_state {
	case .Tutorial:
		rl.ClearBackground({0, 100, 50, 255})
		rl.BeginMode2D(camera)
		mouse_pos = rl.GetScreenToWorld2D(screen_mouse_pos, camera)

		if rl.IsKeyPressed(.ESCAPE) {
			selected_tile = nil
		}

		draw_level(level[1], TILE_SIZE)
		draw_side_bar()

		place_tile()
		handle_animation_controls()
		animate_player()

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
		rl.DrawRectangleRec(play_audio_rect, button_color)
		rl.DrawRectangleLinesEx(play_audio_rect, 2.0, rl.WHITE)

		audio_text := play_audio ? "MUSIC: ON" : "MUSIC: OFF"
		text_width := rl.MeasureText(strings.clone_to_cstring(audio_text), 20)
		rl.DrawText(
			strings.clone_to_cstring(audio_text),
			i32(play_audio_rect.x) + i32(play_audio_rect.width) / 2 - text_width / 2,
			i32(play_audio_rect.y) + 20,
			20,
			rl.WHITE,
		)

		if rl.CheckCollisionPointRec(screen_mouse_pos, play_audio_rect) {
			if rl.IsMouseButtonPressed(.LEFT) {

				play_audio = !play_audio

				if !audio_init {
					initialize_audio()
				}


			}
		}


	case .Instructions_Screen:
		mouse_pos = rl.GetMousePosition()
		draw_instructions_screen()

	case .Gameplay:
		rl.ClearBackground({0, 120, 153, 255})
		rl.BeginMode2D(camera)
		mouse_pos = rl.GetScreenToWorld2D(screen_mouse_pos, camera)

		start_button := rl.Rectangle{225, 625, 200, 50}
		start_text_width := rl.MeasureText("START SIMULATION", 18)
		rl.DrawRectangleRec(start_button, rl.DARKGREEN)
		rl.DrawRectangleLinesEx(start_button, 2.0, rl.WHITE)
		rl.DrawText(
			"START SIMULATION",
			i32(start_button.x) + i32(start_button.width) / 2 - start_text_width / 2,
			i32(start_button.y) + 20,
			18,
			rl.WHITE,
		)

		if rl.CheckCollisionPointRec(mouse_pos, start_button) && rl.IsMouseButtonPressed(.LEFT) {
			start_animation()

		}

		if rl.IsKeyPressed(.ESCAPE) {
			selected_tile = nil
		}

		play_audio_rect = {225, 700, 200, 50}
		rl.DrawRectangleRec(play_audio_rect, button_color)
		rl.DrawRectangleLinesEx(play_audio_rect, 2.0, rl.WHITE)

		audio_text := play_audio ? "MUSIC: ON" : "MUSIC: OFF"
		text_width := rl.MeasureText(strings.clone_to_cstring(audio_text), 20)
		rl.DrawText(
			strings.clone_to_cstring(audio_text),
			i32(play_audio_rect.x) + i32(play_audio_rect.width) / 2 - text_width / 2,
			i32(play_audio_rect.y) + 20,
			20,
			rl.WHITE,
		)

		if rl.CheckCollisionPointRec(mouse_pos, play_audio_rect) {
			if rl.IsMouseButtonPressed(.LEFT) {

				play_audio = !play_audio

				if !audio_init {
					initialize_audio()
				}


			}
		}


		if rl.IsKeyPressed(.R) {
			init_game_state()
			init_player()
			reset_level()
			clear_dynamic_array(&placed_path_tiles)

		}
		draw_level(level[current_level], TILE_SIZE)
		draw_side_bar()

		place_tile()
		handle_animation_controls()
		animate_player()

		draw_game_status()

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

			if game_over_reason == "You've successfully reached the end!" {
				selected_tile = nil
				if rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT) {
					init_game_state()
					reset_level()
					clear_dynamic_array(&placed_path_tiles)
					if current_level + 1 >= LEVEL_COUNT {
						current_game_state = .EndGame
						rl.EndMode2D()
						rl.EndTextureMode()
						return
					}
					get_level(current_level + 1)
					init_player()
				}

				rl.DrawText(
					strings.clone_to_cstring("Press Space or click to go to the next level"),
					440,
					430,
					20,
					rl.WHITE,
				)

			}

		}
		rl.EndMode2D()

	case .EndGame:
		draw_end_screen()
	}

	rl.EndTextureMode()

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	// Apply the CRT effect shader when drawing the render texture
	rl.BeginShaderMode(shaders.crt_effect)

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


	// Draw button background
	tutorial_button_color := rl.DARKBLUE
	if rl.CheckCollisionPointRec(mouse_pos, tutorial_button_rect) {
		tutorial_button_color = rl.BLUE // Highlight on hover

		// Check if button is clicked
		if rl.IsMouseButtonPressed(.LEFT) {
			// Start the tutorial
			current_game_state = .Tutorial
			current_level = 1
			level_grid_copy = level[1]
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
	init_shaders()
	get_level(0)
	target = rl.LoadRenderTexture(1280, 720)
	background_texture = rl.LoadRenderTexture(1280, 720)
	init_camera()


	// game_music = rl.LoadSound("../assets/chunky_monkey_shuffle.mp3")

	play_audio = false

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
	screen_height = i32(h)
	screen_width = i32(w)
	update_render_target = true

	offset_x = f32(w / 4) + f32(TILE_SIZE / 5)
	offset_y = f32(h / 4) - f32(TILE_SIZE * 5) + 20


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
