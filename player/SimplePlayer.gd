extends CharacterBody3D
class_name SimplePlayer

const mouse_sens = 0.022 * 3.0

const unit_conversion = 64.0

const gravity = 32.0
const jumpvel = 0.42*20.0 + gravity/20.0

const max_speed = 4.317
const max_speed_air = 4.317

const accel = 15.0
const accel_air = 15.0

var wish_dir = Vector3()
var friction = 6.0

var original_fov = 90.0
func _ready():
    original_fov = $CameraHolder/Camera3D.fov
    floor_constant_speed = true

func _friction(_velocity : Vector3, delta : float) -> Vector3:
    _velocity *= pow(0.9, delta*60.0)
    if wish_dir == Vector3():
        _velocity = _velocity.move_toward(Vector3(), delta * max_speed)
    return _velocity

func handle_friction(delta):
    var oldvel = velocity
    velocity = _friction(velocity, delta)
    if !is_on_floor():
        velocity.y = oldvel.y


var sprint_strength = 0.0

func handle_accel(delta):
    var actual_maxspeed = max_speed if is_on_floor() else max_speed_air
    var wish_dir_length = wish_dir.length()
    var actual_accel = (accel if is_on_floor() else accel_air) * actual_maxspeed * wish_dir_length
    
    if Input.is_action_pressed("supersprint"):
        actual_maxspeed *= 20.0
        actual_accel *= 20.0
        sprint_strength = move_toward(sprint_strength, 2.0, delta*32.0)
    elif Input.is_action_pressed("sprint"):
        actual_maxspeed *= 6.3/max_speed
        actual_accel *= 6.3/max_speed
        sprint_strength = move_toward(sprint_strength, 1.0, delta*16.0)
    else:
        sprint_strength = move_toward(sprint_strength, 0.0, delta*16.0)
    
    if in_water:
        actual_maxspeed *= 0.7
        actual_accel *= 0.7
        
    if wish_dir != Vector3():
        if in_water:
            var speed_in_wish_dir = velocity.dot(wish_dir.normalized())
            var speed = velocity.length()
            if speed_in_wish_dir < actual_maxspeed:
                var add_limit = actual_maxspeed - speed_in_wish_dir
                var add_amount = min(add_limit, actual_accel*delta)
                velocity += wish_dir.normalized() * add_amount
                if speed > actual_maxspeed:
                    velocity = velocity.normalized() * speed
        else:
            var floor_velocity = Vector3(velocity.x, 0, velocity.z)
            var speed_in_wish_dir = floor_velocity.dot(wish_dir.normalized())
            var speed = floor_velocity.length()
            if speed_in_wish_dir < actual_maxspeed:
                var add_limit = actual_maxspeed - speed_in_wish_dir
                var add_amount = min(add_limit, actual_accel*delta)
                velocity += wish_dir.normalized() * add_amount
                if speed > actual_maxspeed:
                    floor_velocity = velocity * Vector3(1.0, 0.0, 1.0)
                    floor_velocity = floor_velocity.normalized() * speed
                    velocity.x = floor_velocity.x
                    velocity.z = floor_velocity.z

func handle_friction_and_accel(delta):
    handle_friction(delta)
    handle_accel(delta)

@export var do_camera_smoothing : bool = true
@export var do_stairs : bool = true
@export var do_skipping_hack : bool = false
@export var stairs_cause_floor_snap : bool = false
@export var skipping_hack_distance : float = 0.08
@export var step_height : float = 0.5

var started_process_on_floor = false

func check_and_attempt_skipping_hack(distance : float, floor_normal : float):
    # try again with a certain minimum horizontal step distance if there was no wall collision and the wall trace was close
    if !found_stairs and (wall_test_travel * Vector3(1,0,1)).length() < distance:
        # go back to where we were at the end of the ceiling collision test
        global_position = ceiling_position
        # calculate a new path for the wall test: horizontal only, length of our fallback distance
        var floor_velocity = Vector3(velocity.x, 0.0, velocity.z)
        var factor = distance / floor_velocity.length()
        
        # step 2, skipping hack version
        wall_test_travel = floor_velocity * factor
        var info = move_and_collide_n_times(floor_velocity, factor, 2)
        velocity = info[0]
        wall_remainder = info[1]
        wall_collision = info[2]
        
        # step 3, skipping hack version
        floor_collision = move_and_collide(Vector3.DOWN * (ceiling_travel_distance + (step_height if started_process_on_floor else 0.0)))
        if floor_collision and floor_collision.get_collision_count() > 0 and floor_collision.get_normal(0).y > floor_normal:
            found_stairs = true

var found_stairs = false
var wall_test_travel = Vector3()
var wall_remainder = Vector3()
var ceiling_position = Vector3()
var ceiling_travel_distance = Vector3()
var ceiling_collision : KinematicCollision3D = null
var wall_collision : KinematicCollision3D = null
var floor_collision : KinematicCollision3D = null

var slide_snap_offset = Vector3()

func move_and_collide_n_times(vector : Vector3, delta : float, slide_count : int, skip_reject_if_ceiling : bool = true):
    var collision = null
    var remainder = vector
    var adjusted_vector = vector * delta
    var _floor_normal = cos(floor_max_angle)
    for _i in slide_count:
        var new_collision = move_and_collide(adjusted_vector)
        if new_collision:
            collision = new_collision
            remainder = collision.get_remainder()
            adjusted_vector = remainder
            if !skip_reject_if_ceiling or collision.get_normal().y >= -_floor_normal:
                adjusted_vector = adjusted_vector.slide(collision.get_normal())
                vector = vector.slide(collision.get_normal())
        else:
            remainder = Vector3()
            break
    
    return [vector, remainder, collision]

func move_and_climb_stairs(delta : float, allow_stair_snapping : bool):
    var start_position = global_position
    var start_velocity = velocity
    
    found_stairs = false
    wall_test_travel = Vector3()
    wall_remainder = Vector3()
    ceiling_position = Vector3()
    ceiling_travel_distance = Vector3()
    ceiling_collision = null
    wall_collision = null
    floor_collision = null
    
    # do move_and_slide and check if we hit a wall
    wall_min_slide_angle = 0.0
    move_and_slide()
    
    var slide_velocity = velocity
    var slide_position = global_position
    var hit_wall = false
    var floor_normal = cos(floor_max_angle)
    var max_slide = get_slide_collision_count()
    var accumulated_position = start_position
    var wall_position = start_position
    for slide in max_slide:
        var collision = get_slide_collision(slide)
        var y = collision.get_normal().y
        accumulated_position += collision.get_travel()
        if y < floor_normal and y > -floor_normal:
            hit_wall = true
            wall_position = accumulated_position
    slide_snap_offset = accumulated_position - global_position
    
    var really_do_stairs = do_stairs
    if !is_on_floor() and wish_dir == Vector3():
        really_do_stairs = false
    if !is_on_floor() and velocity.y > 0.0:
        really_do_stairs = false
    # if we hit a wall, check for simple stairs; three steps
    if hit_wall and really_do_stairs and (start_velocity.x != 0.0 or start_velocity.z != 0.0):
        var original_wall_dist = ((wall_position - accumulated_position)*Vector3(1,0,1)).length_squared()
        
        global_position = start_position
        velocity = start_velocity
        # step 1: upwards trace
        var up_height = probe_probable_step_height() # NOT NECESSARY. can just be step_height.
        
        ceiling_collision = move_and_collide(up_height * Vector3.UP)
        ceiling_travel_distance = step_height if not ceiling_collision else abs(ceiling_collision.get_travel().y)
        ceiling_position = global_position
        # step 2: "check if there's a wall" trace
        wall_test_travel = velocity * delta
        var info = move_and_collide_n_times(velocity, delta, 2)
        velocity = info[0]
        wall_remainder = info[1]
        wall_collision = info[2]
        
        var wall_test_dist = ((wall_collision.get_travel() if wall_collision else wall_test_travel)*Vector3(1,0,1)).length_squared()
        var went_further = wall_test_dist - 0.00001 > original_wall_dist
        
        # step 3: downwards trace
        floor_collision = move_and_collide(Vector3.DOWN * (ceiling_travel_distance + (step_height if started_process_on_floor else 0.0)))
        if went_further and floor_collision:
            if floor_collision.get_normal(0).y > floor_normal:
                found_stairs = true
            # NOTE: NOT NECESSARY
            # try to skip over small sloped walls if we failed to find a stair and the skipping hack is enabled
            if !floor_collision or floor_collision.get_normal(0).y < floor_normal:
                check_and_attempt_skipping_hack(0.01, floor_normal)
            if !floor_collision or floor_collision.get_normal(0).y < floor_normal and do_skipping_hack:
                check_and_attempt_skipping_hack(skipping_hack_distance, floor_normal)
    
    # (this section is more complex than it needs to be, because of move_and_slide taking velocity and delta for granted)
    # if we found stairs, climb up them
    if found_stairs:
        if allow_stair_snapping and stairs_cause_floor_snap:
            velocity.y = 0.0
        var oldvel = velocity
        velocity = wall_remainder / delta
        move_and_slide()
        velocity = oldvel
    # no stairs, do "normal" non-stairs movement
    else:
        global_position = slide_position
        velocity = slide_velocity
    
    return found_stairs

func probe_probable_step_height():
    const hull_height = 1.75 # edit me
    const center_offset = 0.875 # edit to match the offset between your origin and the center of your hitbox
    const hull_width = 0.625 # approximately the full width of your hull
    
    var heading = (velocity * Vector3(1, 0, 1)).normalized()
    
    var offset = Vector3()
    var test = move_and_collide(heading * hull_width, true)
    if test and abs(test.get_normal().y) < 0.8:
        offset = (test.get_position(0) - test.get_travel() - global_position) * Vector3(1, 0, 1)
    
    var raycast = ShapeCast3D.new()
    var shape = CylinderShape3D.new()
    shape.radius = hull_width/2.0
    shape.height = max(0.01, hull_height - step_height*2.0 - 0.1)
    raycast.shape = shape
    raycast.max_results = 1
    add_child(raycast)
    raycast.collision_mask = collision_mask
    raycast.position = Vector3(0.0, center_offset, 0.0)
    if offset != Vector3():
        raycast.target_position = heading * hull_width * 0.22 + offset
    else:
        raycast.target_position = heading * hull_width * 0.72
    #raycast.force_raycast_update()
    raycast.force_shapecast_update()
    if raycast.is_colliding():
        #raycast.position = raycast.get_collision_point(0)
        raycast.global_position = raycast.get_collision_point(0)
    else:
        raycast.global_position += raycast.target_position
    
    var up_distance = 50.0
    raycast.target_position = Vector3(0.0, 50.0, 0.0)
    #raycast.force_raycast_update()
    raycast.force_shapecast_update()
    if raycast.is_colliding():
        up_distance = raycast.get_collision_point(0).y - raycast.position.y
    
    var down_distance = center_offset
    raycast.target_position = Vector3(0.0, -center_offset, 0.0)
    #raycast.force_raycast_update()
    raycast.force_shapecast_update()
    if raycast.is_colliding():
        down_distance = raycast.position.y - raycast.get_collision_point(0).y
    
    raycast.queue_free()
    
    if up_distance + down_distance < hull_height:
        return step_height
    else:
        var highest = up_distance - center_offset
        var lowest = center_offset - down_distance
        return clamp(highest/2.0 + lowest/2.0, 0.0, step_height)

var world : World = DummySingleton.get_tree().get_first_node_in_group("World")

var prev_position = Vector3i()
func _process(delta: float) -> void:
    prev_position = Vector3i(global_position.round()) + world.world_origin
    started_process_on_floor = is_on_floor()
    # for controller camera control
    #handle_stick_input(delta)
    
    if Input.is_action_just_pressed("farlands_finder"):
        #global_position.x += 8388608.0*8.0*8.0
        global_position.x += 1500.0
    if Input.is_action_just_pressed("farlands_finder_z"):
        global_position.z += 8388608.0*8.0*8.0
    
    var allow_stair_snapping = started_process_on_floor
    var force_jump = Input.is_action_just_pressed("ui_accept")
    if force_jump or (Input.is_action_pressed("ui_accept") and (started_process_on_floor or in_water)):
        allow_stair_snapping = false
        velocity.y = jumpvel
        if in_water:
            velocity.y *= 0.2
        if Input.is_action_pressed("supersprint"):
            velocity.y *= 5.0
        floor_snap_length = 0.0
    elif started_process_on_floor:
        floor_snap_length = step_height + safe_margin
    
    var input_dir := Input.get_vector("left", "right", "forward", "backward")# + Input.get_vector("stick_left", "stick_right", "stick_forward", "stick_backward")
    if !in_water:
        wish_dir = Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, $CameraHolder.global_rotation.y)
        if wish_dir.length_squared() > 1.0:
            wish_dir = wish_dir.normalized()
    else:
        wish_dir = $CameraHolder.basis * Vector3(input_dir.x, 0, input_dir.y)
    
    handle_friction_and_accel(delta)
    
    var grav_mod = 1.0
    var drag = 0.98
    
    if in_water:
        if wish_dir != Vector3():
            grav_mod = 0.0
        else:
            grav_mod = 0.4
        drag = 0.5
    
    var start_pos = global_position
    var start_vel = velocity
    
    actually_handle_movement(delta, drag, grav_mod, allow_stair_snapping)
    
    var chunk = check_chunk(start_pos, start_vel)
    if !chunk:
        print("inside non-existent chunk...")
        actually_handle_movement(delta, drag, grav_mod, allow_stair_snapping)
        chunk = check_chunk(start_pos, start_vel)
    
    var is_solid = func(id : int):
        if id == 0:
            return false
        var type = Voxels.GlobalMesher.vox_get_type_pub(id)
        return type == 0 or type == 1
    
    if chunk:
        var pos = global_position
        if is_solid.call(world.get_block_with_origin(pos + Vector3(0, 0.01, 0))):
            global_position.y += 0.5
        if is_solid.call(world.get_block_with_origin(pos + Vector3(0, 0.5, 0))):
            global_position.y += 0.5
        if is_solid.call(world.get_block_with_origin(pos + Vector3(0, 1.0, 0))):
            global_position.y += 0.5
        if is_solid.call(world.get_block_with_origin(pos + Vector3(0, 1.5, 0))):
            global_position.y += 0.5
    
    $OverlayLayer/WaterOverlay.visible = head_in_water
    
    handle_camera_adjustment(start_pos, delta)
    
    handle_movement_sound(started_process_on_floor, is_on_floor(), start_vel, delta)
    
    cached_position = global_position
    cached_facing_dir = $CameraHolder.basis * Vector3.FORWARD

func get_standing_voxel():
    if !is_on_floor() and in_water:
        return 6
    var below = global_position - Vector3.UP*0.5
    var vox = world.get_block_with_origin(below)
    #if vox == 0: vox = world.get_block(prev_position - Vector3i.UP)
    if vox == 0 or vox == 6: vox = world.get_block_with_origin(below + Vector3( 0.45, 0.0, -0.45))
    if vox == 0 or vox == 6: vox = world.get_block_with_origin(below + Vector3( 0.45, 0.0,  0.45))
    if vox == 0 or vox == 6: vox = world.get_block_with_origin(below + Vector3(-0.45, 0.0, -0.45))
    if vox == 0 or vox == 6: vox = world.get_block_with_origin(below + Vector3(-0.45, 0.0,  0.45))
    return vox

static func get_vox_sound_prefix(vox : int):
    match vox:
        1: return "grass"
        2: return "dirt"
        3: return "rock"
        4: return "wood"
        14: return "sand"
        -1: return "place"
        _: return "grass"

static var prev_which = ""
static func generate_sound(vox, kind, parent, where : Vector3 = Vector3(), channel = "SFX"):
    var prefix = get_vox_sound_prefix(vox) if vox is int else vox
    var which = ["_a", "_b", "_c", "_d"].pick_random()
    while which == prev_which:
        which = ["_a", "_b", "_c", "_d"].pick_random()
    prev_which = which
    EmitterFactory.emit(prefix+kind+which, parent, where, channel)

func generate_step_sound():
    var vox = get_standing_voxel()
    generate_sound(vox, "step", self, Vector3(), "SFX" if !in_water else "SFX Wet")

var step_progress = 0.0
const step_rate_modifier = 0.6
var prev_in_water = false
func handle_movement_sound(started_process_on_floor : bool, now_on_floor : bool, start_vel : Vector3, delta : float):
    var speed = start_vel.length()
    if prev_in_water and !in_water:
        generate_sound("leavewater", "", self, Vector3(), "SFX")
        step_progress = 0.0
    if !prev_in_water and in_water and speed > 10.0:
        generate_sound("splash", "", self, Vector3(), "SFX")
        step_progress = 0.0
    
    prev_in_water = in_water
        
    var i = AudioServer.get_bus_index("SFX")
    AudioServer.set_bus_effect_enabled(i, 0, head_in_water)
    AudioServer.set_bus_effect_enabled(i, 1, head_in_water)
    
    if is_on_floor() and !started_process_on_floor:
        step_progress = 0.5
    
    if !is_on_floor() and !in_water:
        pass
    else:
        if speed == 0.0:
            step_progress = 0.85
        else:
            step_progress += delta * min(7.0, speed) * step_rate_modifier
            if !started_process_on_floor and now_on_floor and start_vel.y < -1.0:
                step_progress = 0.0
                generate_step_sound()
            else:
                if step_progress > 1.0:
                    if in_water:
                        generate_sound("leavewater", "", self, Vector3(), "SFX")
                    generate_step_sound()
                    step_progress = fmod(step_progress, 1.0)

func check_chunk(start_pos, start_vel):
    var prev_chunk_coord = World.get_chunk_coord(start_pos) + world.world_origin
    #var prev_chunk = world.chunks_loaded.get(prev_chunk_coord)
    
    var chunk_coord = World.get_chunk_coord(global_position) + world.world_origin
    var chunk = world.chunks_loaded.get(chunk_coord)
    
    if not chunk or not chunk.remeshed:
        $DebugLabel.text = str(prev_chunk_coord)
        global_position = start_pos
        
        var d : Vector3 = prev_chunk_coord - chunk_coord
        d = d.clamp(-Vector3.ONE, Vector3.ONE)
        
        velocity = start_vel
        if d.y != 0:
            velocity.y = 0
        
        if d.x == 0 and d.z != 0:
            velocity.z = 0
        elif d.z == 0 and d.x != 0:
            velocity.x = 0
        elif abs(velocity.x) < abs(velocity.z):
            velocity.x = 0
        else:
            velocity.z = 0
        
        return null
    else:
        var d = Voxels.GlobalGenerator.pub_true_height_at_global(Vector3i(global_position.round()) + world.world_origin)
        $DebugLabel.text = "%s\n%s\n%s\n%s" % [Vector3i(global_position.round()) + world.world_origin, chunk_coord, global_position.snapped(Vector3.ONE*0.1), d]
        var up_offset = 0.7 if !in_water else 0.3
        var block_in = world.get_block_with_origin(global_position + Vector3.UP*up_offset)
        var head_block_in = world.get_block_with_origin(global_position + Vector3.UP*1.5)
        in_water = block_in == 6 or head_block_in == 6
        head_in_water = world.get_block_with_origin($CameraHolder.global_position + Vector3.UP/8.0) == 6
        return chunk

func actually_handle_movement(delta, drag, grav_mod, allow_stair_snapping):
    if not is_on_floor():
        velocity.y -= gravity * delta * 0.5 * grav_mod
        velocity.y *= pow(drag, delta*10.0)
    
    # CHANGE ME: replace this with your own movement-and-stair-climbing code
    move_and_climb_stairs(delta, allow_stair_snapping)
    
    #print(global_position.y)
    
    if not is_on_floor(): 
        velocity.y -= gravity * delta * 0.5 * grav_mod
        velocity.y *= pow(drag, delta*10.0)

func refresh_probe():
    $ReflectionProbe.max_distance = randf_range(64.0, 65.0)

var in_water : bool = false
var head_in_water : bool = false

var cached_position = Vector3()
var cached_facing_dir = Vector3.FORWARD

const stick_camera_speed = 240.0
func handle_stick_input(_delta):
    pass
    #var camera_dir := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.15)
    #var tilt = camera_dir.length()
    #var acceleration = lerp(0.25, 1.0, tilt)
    #camera_dir *= acceleration
    #$CameraHolder.rotation_degrees.y -= camera_dir.x * stick_camera_speed * delta
    #$CameraHolder.rotation_degrees.x -= camera_dir.y * stick_camera_speed * delta
    #$CameraHolder.rotation_degrees.x = clamp($CameraHolder.rotation_degrees.x, -90.0, 90.0)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            $CameraHolder.rotation_degrees.y -= event.relative.x * mouse_sens
            $CameraHolder.rotation_degrees.x -= event.relative.y * mouse_sens
            $CameraHolder.rotation_degrees.x = clamp($CameraHolder.rotation_degrees.x, -90.0, 90.0)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        if event.pressed and event.keycode in [KEY_ESCAPE, KEY_Z]:
            if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            else:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

@export var third_person : bool = false
@export var camera_smoothing_meters_per_sec : float = 3.0
# used to smooth out the camera when climbing stairs
var camera_offset_y = 0.0
func handle_camera_adjustment(start_position, delta):
    $CameraHolder/Camera3D.fov = rad_to_deg(atan(sprint_strength*0.1 + tan(deg_to_rad(original_fov/2.0))))*2.0
    
    # first/third-person adjustment
    $CameraHolder.position.y = 1.2 if third_person else 1.625
    $CameraHolder/Camera3D.position.z = 1.5 if third_person else 0.0
    
    if do_camera_smoothing:
        # NOT NEEDED: camera smoothing
        var stair_climb_distance = 0.0
        if found_stairs:
            stair_climb_distance = global_position.y - start_position.y
        elif is_on_floor():
            stair_climb_distance = -slide_snap_offset.y
        
        camera_offset_y -= stair_climb_distance
        camera_offset_y = clamp(camera_offset_y, -step_height, step_height)
        camera_offset_y = move_toward(camera_offset_y, 0.0, delta * camera_smoothing_meters_per_sec)
        
        $CameraHolder/Camera3D.position.y = 0.0
        $CameraHolder/Camera3D.position.x = 0.0
        $CameraHolder/Camera3D.global_position.y += camera_offset_y

func use_selected_block():
    return $ActiveInventory.use_selected_block()

func pick_block(vox : int):
    return $ActiveInventory.pick_block(vox)

static func make_debug_mesh(color : Color):
    var texture = GradientTexture2D.new()
    texture.fill_from = Vector2(0.5, 0.5)
    texture.fill_to = Vector2(0.5, 1.0)
    texture.fill = GradientTexture2D.FILL_RADIAL
    texture.gradient = Gradient.new()
    texture.gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
    texture.gradient.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
    texture.gradient.remove_point(0)
    texture.gradient.remove_point(0)
    texture.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
    
    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = color
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.albedo_texture = texture
    
    var mesh = QuadMesh.new()
    mesh.size = Vector2(0.25, 0.25)
    mesh.material = mat
    
    return mesh

@onready var _collision_debug_mesh = SimplePlayer.make_debug_mesh(Color(1.0, 0.75, 0.5, 0.5))
@onready var _collision_debug_mesh_unwalkable = SimplePlayer.make_debug_mesh(Color(1.0, 0.0, 0.0, 0.5))

class Visualizer extends MeshInstance3D:
    var life = 5.0
    func _process(delta):
        life -= delta
        if life < 0.0:
            queue_free()
        else:
            transparency = 1.0 - life/5.0

var _debug_timer_max = 0.016
var _debug_timer = _debug_timer_max
func add_collision_debug_visualizer(delta):
    _debug_timer -= delta
    if _debug_timer > 0.0:
        return
    _debug_timer += _debug_timer_max
    if _debug_timer < 0.0:
        _debug_timer = 0.0
    
    var collision = floor_collision if floor_collision else wall_collision
    if collision:
        var normal = collision.get_normal(0)
        if true:#normal.y > 0.1 and normal.y < 0.999:
            var visualizer = Visualizer.new() as Visualizer
            if acos(normal.y) < floor_max_angle:
                visualizer.mesh = _collision_debug_mesh
            else:
                visualizer.mesh = _collision_debug_mesh_unwalkable
            DummySingleton.get_tree().current_scene.add_child(visualizer)
            if normal.round().abs() != Vector3.UP:
                visualizer.look_at_from_position(Vector3(), normal)
            else:
                visualizer.look_at_from_position(Vector3(), normal, Vector3.RIGHT)
            visualizer.global_position = collision.get_position(0)
            visualizer.global_position += normal*0.01
