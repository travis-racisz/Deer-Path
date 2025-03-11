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

run: bool
texture: rl.Texture
texture2: rl.Texture

mouse_pos: rl.Vector2
selected_tile: TileType
level: [1]Level
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
TILE_SIZE :: 64

// Initialize in your init procedure

ripple_texture: rl.Texture

camera: rl.Camera2D

tile_placement_anim: struct {
	active:     bool,
	position:   rl.Vector2,
	start_time: f32,
	duration:   f32,
}

trigger_tile_placement_effect :: proc(x, y: i32) {
	tile_placement_anim.active = true
	tile_placement_anim.position = {f32(x + 50), f32(y + 50)} // Center of tile
	tile_placement_anim.start_time = f32(rl.GetTime())
	tile_placement_anim.duration = 1.8 // Animation lasts 0.8 seconds
	//
	rl.SetShaderValueV(
		ripple_shader,
		rl.GetShaderLocation(ripple_shader, "u_center"),
		&tile_placement_anim.position,
		.VEC2,
		1,
	)
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
			rl.BeginShaderMode(ripple_shader)
			rl.DrawTexture(
				ripple_texture,
				i32(tile_placement_anim.position.x - 50),
				i32(tile_placement_anim.position.y - 50),
				rl.WHITE,
			)
			rl.EndShaderMode()


		}
	}
}

SpriteAssets :: struct {
	fire:  [8]rl.Texture,
	grass: rl.Texture,
	deer:  rl.Texture,
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

AStarNode :: struct {
	position: PathTile,
	g_score:  int,
	f_score:  int,
	h_score:  int,
	parent:   ^AStarNode,
}

ResourceSet :: struct {
	path_tiles:     i32,
	dirt_tiles:     i32,
	bridge_tiles:   i32,
	hunting_ground: i32,
}

LEVEL_COUNT :: 1


GameState :: enum {
	Title_Screen,
	Instructions_Screen,
	Gameplay,
}

shaders: struct {
	path_flow:                rl.Shader,
	fire_distortion:          rl.Shader,
	tile_placement:           rl.Shader,
	crt_effect:               rl.Shader,

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
}


init_shaders :: proc() {
	// Load shaders
	shaders.path_flow = rl.LoadShader(nil, "assets/shaders/path_flow.fs")
	shaders.fire_distortion = rl.LoadShader(nil, "assets/shaders/fire_distortion.fs")
	shaders.tile_placement = rl.LoadShader(nil, "assets/shaders/tile_placement.fs")
	shaders.texture0_loc = rl.GetShaderLocation(shaders.fire_distortion, "texture0")
	ripple_shader = rl.LoadShader(nil, "ripple.fs")


	fmt.println(
		"Shader IDs - Path:",
		shaders.path_flow.id,
		"Fire:",
		shaders.fire_distortion.id,
		"Tile:",
		shaders.tile_placement.id,
	)
	resolution := [2]f32{1280, 720}

	// If any shader ID is 0, the shader failed to load
	if shaders.tile_placement.id == 0 {
		fmt.println("ERROR: Tile placement shader failed to load")
	}
	// Get uniform locations
	// For path flow shader
	shaders.path_flow_time_loc = rl.GetShaderLocation(shaders.path_flow, "time")
	shaders.path_flow_resolution_loc = rl.GetShaderLocation(shaders.path_flow, "resolution")

	time := rl.GetTime()
	rl.SetShaderValue(ripple_shader, rl.GetShaderLocation(ripple_shader, "u_time"), &time, .FLOAT)
	shaders.crt_effect = rl.LoadShader(nil, "assets/shaders/crt_effect.fs")

	// Get uniform locations for CRT shader
	shaders.crt_resolution_loc = rl.GetShaderLocation(shaders.crt_effect, "resolution")
	shaders.crt_time_loc = rl.GetShaderLocation(shaders.crt_effect, "time")
	shaders.crt_texture0_loc = rl.GetShaderLocation(shaders.crt_effect, "texture0")

	// Set initial values for CRT shader
	rl.SetShaderValue(shaders.crt_effect, shaders.crt_resolution_loc, &resolution, .VEC2)

	rl.SetShaderValueV(
		ripple_shader,
		rl.GetShaderLocation(ripple_shader, "u_resolution"),
		&resolution,
		.VEC2,
		1,
	)


	// For fire distortion shader
	shaders.fire_time_loc = rl.GetShaderLocation(shaders.fire_distortion, "time")
	shaders.fire_texture0_loc = rl.GetShaderLocation(shaders.fire_distortion, "texture0")

	// For tile placement shader
	shaders.tile_time_loc = rl.GetShaderLocation(shaders.tile_placement, "time")
	shaders.tile_pos_loc = rl.GetShaderLocation(shaders.tile_placement, "tilePos")
	shaders.tile_resolution_loc = rl.GetShaderLocation(shaders.tile_placement, "resolution")

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
			if level[0].grid[next_row][next_col] != .Path &&
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
		640 - (rl.MeasureText(strings.clone_to_cstring(title_text), 80) / 4),
		150,
		80,
		rl.WHITE,
	)

	// Draw subtitle
	subtitle_text := "A Survival Journey"
	rl.DrawText(strings.clone_to_cstring(subtitle_text), 640, 250, 40, rl.WHITE)

	// Draw start button
	button_width := 200
	button_height := 60
	button_x := 640 + button_width
	button_y := 400

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
		640 - rl.MeasureText(strings.clone_to_cstring(title_text), 60) / 2,
		50,
		60,
		rl.WHITE,
	)

	// Draw instruction texts
	instructions := []string {
		"1. Build a path from the starting point to the end goal",
		"2. Use your limited supply of path tiles wisely",
		"3. BEWARE: The deer will walk on ALL tiles in the ORDER you placed them!",
		"4. Avoid placing paths near predators or fire",
		"5. Fire will spread each turn, so plan ahead",
		"6. Press SPACE to start the deer's journey once your path is complete",
		"7. Press R to reset the level if needed",
	}

	y_pos := 150
	for instruction in instructions {
		text_color := instruction == instructions[2] ? rl.YELLOW : rl.WHITE // Highlight the important rule
		font_size := instruction == instructions[2] ? 25 : 24 // Make important rule slightly bigger

		rl.DrawText(
			strings.clone_to_cstring(instruction),
			200,
			i32(y_pos),
			i32(font_size),
			text_color,
		)

		y_pos += 50
	}

	// Draw emphasized warning
	warning_text := "Remember: The deer follows ALL placed tiles in placement order!"
	rl.DrawText(
		strings.clone_to_cstring(warning_text),
		640 - rl.MeasureText(strings.clone_to_cstring(warning_text), 30) / 2,
		480,
		30,
		rl.YELLOW,
	)

	// Draw start button
	button_width: i32 = 300
	button_height: i32 = 60
	button_x: i32 = 640 - button_width / 2
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
			if level[0].grid[next_row][next_col] == .Path && !visited[next_row][next_col] {
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
	start_row := int(level[0].start_position.y / TILE_SIZE)
	start_col := int(level[0].start_position.x / TILE_SIZE)
	end_row := int(level[0].end_position.y)
	end_col := int(level[0].end_position.x)

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
	player_position = level[0].start_position
	player_position.x = player_position.x * TILE_SIZE + 250 // Adjust for grid rendering offset
	player_position.y = player_position.y * TILE_SIZE

	// Initially, target position is the same as player position
	target_position = player_position

	current_path_index = 0
	is_animating = false
	animation_done = false
}


start_animation :: proc() {
	if is_path_valid && !is_animating && !animation_done {
		start_row := int(level[0].start_position.y / TILE_SIZE)
		start_col := int(level[0].start_position.x / TILE_SIZE)
		end_row := int(level[0].end_position.y)
		end_col := int(level[0].end_position.x)

		movement_path = find_path_bfs(start_row, start_col, end_row, end_col)

		if len(movement_path) > 0 {
			is_animating = true
			current_path_index = 0

			// Set initial target
			target_position.x = f32(movement_path[0].col * TILE_SIZE + 250)
			target_position.y = f32(movement_path[0].row * TILE_SIZE)
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
		target_position.x = f32(movement_path[current_path_index].col * TILE_SIZE + 250)
		target_position.y = f32(movement_path[current_path_index].row * TILE_SIZE)
		current_path_index += 1
		return true
	} else {
		// No more path tiles, move to the end position
		target_position.x = f32(level[0].end_position.x * TILE_SIZE + 250)
		target_position.y = f32(level[0].end_position.y * TILE_SIZE)
		return false
	}
}

// The main animation function
// Add these global variables for turn-based timing

// Modify the animate_player function to be turn-based with visual delays
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
		y      = f32(sprite_assets.deer.height),
		width  = f32(-sprite_assets.deer.width),
		height = f32(sprite_assets.deer.height),
	}

	dest := rl.Rectangle {
		x      = player_position.x + TILE_SIZE / 2,
		y      = player_position.y + TILE_SIZE / 2,
		height = f32(sprite_assets.deer.height),
		width  = f32(sprite_assets.deer.width),
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
	rl.BeginShaderMode(shaders.path_flow)

	for tile in placed_path_tiles {
		x := tile.col * TILE_SIZE + 250
		y := tile.row * TILE_SIZE

		// Draw path tile with shader
		rl.DrawRectangle(i32(x), i32(y), TILE_SIZE, TILE_SIZE, rl.GREEN)
	}

	rl.EndShaderMode()

	// Draw outlines without shader
	for tile in placed_path_tiles {
		x := tile.col * TILE_SIZE + 250
		y := tile.row * TILE_SIZE
		rl.DrawRectangleLines(i32(x), i32(y), TILE_SIZE, TILE_SIZE, rl.DARKGREEN)
	}
}
// Helper function for absolute value
abs :: proc(x: int) -> int {
	return x >= 0 ? x : -x
}

get_level :: proc(level_number: int) -> Level {
	assert(level_number >= 0 && level_number < LEVEL_COUNT)
	level = [1]Level {
		//level 1 
		{
			grid = [10][10]TileType {
				{.Empty, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Empty, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
				{.Meadow, .Fire, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
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
				{.Meadow, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass, .Grass},
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
			level_name = "Straight Ahead",
			level_number = 1,
		},
	}
	level_grid_copy = level[level_number]
	return level[level_number]
}


draw_level :: proc(level: Level, tile_size: int) {
	start_x := i32(level.start_position.x * f32(tile_size) + 250)
	start_y := i32(level.start_position.y * f32(tile_size))
	end_x := i32(level.end_position.x * f32(tile_size) + 250)
	end_y := i32(level.end_position.y * f32(tile_size))

	// Draw start position with a distinct marker
	rl.DrawCircle(start_x + 50, start_y + 50, 40, rl.DARKGREEN)
	rl.DrawCircle(start_x + 50, start_y + 50, 30, rl.GREEN)
	rl.DrawText(
		strings.clone_to_cstring("START"),
		start_x + 50 - rl.MeasureText(strings.clone_to_cstring("START"), 16) / 2,
		start_y + 45,
		16,
		rl.BLACK,
	)

	// Draw end position with a distinct marker
	rl.DrawRectangle(end_x, end_y, 64, 64, rl.YELLOW)
	rl.DrawText(
		strings.clone_to_cstring("END"),
		end_x + 50 - rl.MeasureText(strings.clone_to_cstring("END"), 20) / 2,
		end_y + 40,
		20,
		rl.WHITE,
	)
	for row in 0 ..< 10 {
		for col in 0 ..< 10 {
			// Calculate screen position
			x := col * tile_size
			y := row * tile_size

			// Get the current tile type
			tile := level.grid[row][col]

			// Draw the appropriate sprite/color based on tile type
			rect := rl.Rectangle {
				x      = f32(x) + 250,
				y      = f32(y),
				width  = f32(tile_size),
				height = f32(tile_size),
			}

			// Choose color based on tile type
			color := rl.WHITE // Default

			#partial switch tile {
			case .Empty:
				color = rl.WHITE
				rl.DrawRectangleRec(rect, color)
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
				// Draw a path texture
				rl.DrawRectangle(i32(rect.x) + 30, i32(rect.y) + 10, 40, 80, rl.BEIGE)
				rl.DrawRectangleLinesEx({rect.x + 30, rect.y + 10, 40, 80}, 1, rl.BROWN)
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
				rl.DrawRectangleRec(rect, rl.WHITE)
				rl.BeginShaderMode(shaders.fire_distortion)
				rl.DrawTextureEx(get_fire_texture(), {rect.x, rect.y}, 0, 1.25, rl.WHITE)
				rl.EndShaderMode()
			//rl.DrawTexture(get_fire_texture(), i32(rect.x), i32(rect.y), rl.WHITE)

			}

			// Draw the tile

			// Draw grid lines
			rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)


			// draw the winning tile 
			rl.DrawRectangle(
				i32(level.end_position.x * TILE_SIZE + 250),
				i32(level.end_position.y * TILE_SIZE),
				TILE_SIZE,
				TILE_SIZE,
				rl.BLACK,
			)
		}
	}
}


place_tile :: proc() {

	if is_animating || game_over {
		return
	}

	for row in 0 ..< 10 {
		for col in 0 ..< 10 {
			x := col * TILE_SIZE
			y := row * TILE_SIZE


			rect := rl.Rectangle {
				x      = f32(x) + 250,
				y      = f32(y),
				width  = f32(TILE_SIZE),
				height = f32(TILE_SIZE),
			}
			if rl.CheckCollisionPointRec(mouse_pos, rect) {
				if selected_tile != nil {
					if level[0].grid[row][col] != .Fire && level[0].grid[row][col] != .Predator {
						// Draw semi-transparent overlay
						rl.DrawRectangleRec(rect, {0, 255, 0, 64})
						rl.DrawRectangleLinesEx(rect, 3, rl.GREEN)
					} else {
						// Show invalid placement indicator
						rl.DrawRectangleRec(rect, {255, 0, 0, 64})
						rl.DrawRectangleLinesEx(rect, 3, rl.RED)
					}
					if rl.IsMouseButtonPressed(.LEFT) {
						if level[0].available_resources.path_tiles > 0 {

							if !is_position_in_path(row, col) {
								path_tile := PathTile {
									row = row,
									col = col,
								}
								if level[0].grid[row][col] != .Fire &&
								   level[0].grid[row][col] != .Predator {

									append(&placed_path_tiles, path_tile)
									level[0].available_resources.path_tiles -= 1
									level[0].grid[row][col] = selected_tile

									trigger_tile_placement_effect(i32(x + 250), i32(y))
								}

							}
						}

					}
				}
				validate_path()

				if rl.IsMouseButtonPressed(.RIGHT) {
					tile_type := level[0].grid[row][col]
					if tile_type == .Path {
						idx := find_path_tile_index(row, col)
						if idx > 0 {
							ordered_remove(&placed_path_tiles, idx)
							level[0].available_resources.path_tiles += 1

							level[0].grid[row][col] = level_grid_copy.grid[row][col]
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
	height: i32 = rl.GetScreenHeight() // Match window height

	// Draw panel background with a subtle gradient
	rl.DrawRectangleGradientV(0, 0, width, height, rl.LIGHTGRAY, {220, 220, 220, 255})
	rl.DrawRectangleLinesEx({0, 0, f32(width), f32(height)}, 2, rl.DARKGRAY)

	// Draw title
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
	path_text := fmt.tprintf("Path Tiles: %d", level[0].available_resources.path_tiles)
	rl.DrawText(strings.clone_to_cstring(path_text), 30, 100, 16, rl.BLACK)

	// Visual indicators for resources
	resources_y := i32(130)
	for i in 0 ..< level[0].available_resources.path_tiles {
		if i >= 10 { 	// Show max 10 indicators to avoid clutter
			break
		}
		x_pos := 30 + (i % 5) * 30
		y_pos := resources_y + (i / 5) * 30
		rl.DrawRectangle(x_pos, y_pos, 20, 20, rl.GREEN)
		rl.DrawRectangleLines(x_pos, y_pos, 20, 20, rl.DARKGREEN)
	}

	// === TILE SELECTION SECTION ===
	rl.DrawText(strings.clone_to_cstring("SELECT TILE:"), 20, 200, 18, rl.DARKBLUE)

	// Draw tile selection options with better visual feedback
	grass := rl.Rectangle{50, 230, 50, 50}

	// Check if this tile type is selected
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

	// Game status at the bottom of the panel
	if is_path_valid {
		rl.DrawText(strings.clone_to_cstring("Path is VALID"), 20, height - 60, 20, rl.GREEN)
		rl.DrawText(
			strings.clone_to_cstring("Press SPACE to start"),
			20,
			height - 35,
			16,
			rl.DARKGREEN,
		)
	} else if len(placed_path_tiles) > 0 {
		rl.DrawText(strings.clone_to_cstring("Path is INVALID"), 20, height - 60, 20, rl.RED)
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
	player_row := int((player_position.y) / TILE_SIZE)
	player_col := int((player_position.x - 250) / TILE_SIZE)

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

		// Check bounds
		if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
			continue
		}

		// Check for danger tiles
		tile := level[0].grid[next_row][next_col]

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
	// First, identify all fire tiles and potential spread locations
	fire_tiles: [dynamic]PathTile

	// Find all current fire tiles
	for row in 0 ..< 10 {
		for col in 0 ..< 10 {
			if level[0].grid[row][col] == .Fire {
				append(&fire_tiles, PathTile{row = row, col = col})
			}
		}
	}

	// For each fire tile, attempt to spread
	new_fire_tiles: [dynamic]PathTile

	for fire in fire_tiles {
		// Check adjacent tiles (orthogonal only for fire spread)
		directions := [][2]int{{0, 1}, {1, 0}, {0, -1}, {-1, 0}}

		for dir in directions {
			next_row := fire.row + dir[0]
			next_col := fire.col + dir[1]

			// Check bounds
			if next_row < 0 || next_row >= 10 || next_col < 0 || next_col >= 10 {
				continue
			}

			// Check if tile can catch fire (only grass and meadow can)
			tile := level[0].grid[next_row][next_col]

			if (tile == .Grass || tile == .Meadow) && rand.float32() < fire_spread_chance {
				append(&new_fire_tiles, PathTile{row = next_row, col = next_col})
			}
		}
	}

	// Set the new fire tiles
	for new_fire in new_fire_tiles {
		level[0].grid[new_fire.row][new_fire.col] = .Fire
	}

	// Clean up dynamic arrays
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

		// Draw semi-transparent background
		rl.DrawRectangle(300, 250, 680, 220, {bg_color.r, bg_color.g, bg_color.b, 200})

		// Draw game over message
		status_text := player_won ? "LEVEL COMPLETE!" : "GAME OVER"
		rl.DrawText(strings.clone_to_cstring(status_text), 420, 280, 40, text_color)

		// Draw reason
		rl.DrawText(strings.clone_to_cstring(game_over_reason), 340, 340, 30, text_color)

		// Draw restart instruction
		rl.DrawText(strings.clone_to_cstring("Press 'R' to restart"), 440, 400, 20, text_color)
	} else if is_animating {
		// Show the current turn during animation
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

}

update :: proc() {
	rl.BeginDrawing()
	rl.SetMouseScale(.8, .8)
	mouse_pos = rl.GetWorldToScreen2D(mouse_pos, camera)
	update_animations()

	// Handle different game states
	switch current_game_state {
	case .Title_Screen:
		mouse_pos = rl.GetMousePosition()
		draw_title_screen()

	case .Instructions_Screen:
		mouse_pos = rl.GetMousePosition()
		draw_instructions_screen()

	case .Gameplay:
		rl.BeginShaderMode(shaders.fire_distortion)
		rl.ClearBackground({0, 120, 153, 255})
		rl.BeginMode2D(camera)


		rl.EndShaderMode()
		if rl.IsKeyPressed(.ESCAPE) || rl.IsMouseButtonPressed(.RIGHT) {
			selected_tile = nil
		}
		mouse_pos = rl.GetMousePosition()

		place_tile()
		draw_level(level[0], TILE_SIZE)
		highlight_path()
		draw_side_bar()

		handle_animation_controls()
		animate_player()

		update_and_draw_tile_effects()
		// Draw animation instructions
		draw_game_status()

		// Draw animation instructions

		if game_over {
			if rl.IsKeyPressed(.R) {
				init_game_state()
				init_player()
				reset_level()
				clear_dynamic_array(&placed_path_tiles)
			}

			// Add a button to return to title screen
			if rl.IsKeyPressed(.ESCAPE) {
				current_game_state = .Title_Screen
			}

			// Draw return to title text
			rl.DrawText(
				strings.clone_to_cstring("Press ESC to return to title"),
				440,
				430,
				20,
				rl.WHITE,
			)
		}
		rl.EndMode2D()

	}

	rl.EndDrawing()

	// Anything allocated using temp allocator is invalid after this.
	free_all(context.temp_allocator)
}

// Modify your init procedure to initialize the game state
init :: proc() {
	run = true
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Deer Path - A Survival Journey")
	level = get_level(0)
	init_shaders()
	target = rl.LoadRenderTexture(1280, 720)
	init_camera()


	// Initialize game to title screen
	current_game_state = .Gameplay
	load_sprites()
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	unload_all_sprites()
	unload_shaders()
	rl.CloseWindow()
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
