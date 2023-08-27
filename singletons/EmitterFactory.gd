extends Node

var sounds = {
    "dirthit_a" : preload("res://sfx/dirthit_a.wav"),
    "dirthit_b" : preload("res://sfx/dirthit_b.wav"),
    "dirthit_c" : preload("res://sfx/dirthit_c.wav"),
    "dirthit_d" : preload("res://sfx/dirthit_d.wav"),
    "dirtstep_a" : preload("res://sfx/dirtstep_a.wav"),
    "dirtstep_b" : preload("res://sfx/dirtstep_b.wav"),
    "dirtstep_c" : preload("res://sfx/dirtstep_c.wav"),
    "dirtstep_d" : preload("res://sfx/dirtstep_d.wav"),
    
    "grasshit_a" : preload("res://sfx/grasshit_a.wav"),
    "grasshit_b" : preload("res://sfx/grasshit_b.wav"),
    "grasshit_c" : preload("res://sfx/grasshit_c.wav"),
    "grasshit_d" : preload("res://sfx/grasshit_d.wav"),
    "grassstep_a" : preload("res://sfx/grassstep_a.wav"),
    "grassstep_b" : preload("res://sfx/grassstep_b.wav"),
    "grassstep_c" : preload("res://sfx/grassstep_c.wav"),
    "grassstep_d" : preload("res://sfx/grassstep_d.wav"),
    
    "rockhit_a" : preload("res://sfx/rockhit_a.wav"),
    "rockhit_b" : preload("res://sfx/rockhit_b.wav"),
    "rockhit_c" : preload("res://sfx/rockhit_c.wav"),
    "rockhit_d" : preload("res://sfx/rockhit_d.wav"),
    "rockstep_a" : preload("res://sfx/rockstep_a.wav"),
    "rockstep_b" : preload("res://sfx/rockstep_b.wav"),
    "rockstep_c" : preload("res://sfx/rockstep_c.wav"),
    "rockstep_d" : preload("res://sfx/rockstep_d.wav"),
    
    "woodhit_a" : preload("res://sfx/woodhit_a.wav"),
    "woodhit_b" : preload("res://sfx/woodhit_b.wav"),
    "woodhit_c" : preload("res://sfx/woodhit_c.wav"),
    "woodhit_d" : preload("res://sfx/woodhit_d.wav"),
    "woodstep_a" : preload("res://sfx/woodstep_a.wav"),
    "woodstep_b" : preload("res://sfx/woodstep_b.wav"),
    "woodstep_c" : preload("res://sfx/woodstep_c.wav"),
    "woodstep_d" : preload("res://sfx/woodstep_d.wav"),
    
    "sandhit_a" : preload("res://sfx/sandhit_a.wav"),
    "sandhit_b" : preload("res://sfx/sandhit_b.wav"),
    "sandhit_c" : preload("res://sfx/sandhit_c.wav"),
    "sandhit_d" : preload("res://sfx/sandhit_d.wav"),
    "sandstep_a" : preload("res://sfx/sandstep_a.wav"),
    "sandstep_b" : preload("res://sfx/sandstep_b.wav"),
    "sandstep_c" : preload("res://sfx/sandstep_c.wav"),
    "sandstep_d" : preload("res://sfx/sandstep_d.wav"),
    
    "place_a" : preload("res://sfx/place_a.wav"),
    "place_b" : preload("res://sfx/place_b.wav"),
    "place_c" : preload("res://sfx/place_c.wav"),
    "place_d" : preload("res://sfx/place_d.wav"),
    
    "leavewater_a" : preload("res://sfx/leavewater_a.wav"),
    "leavewater_b" : preload("res://sfx/leavewater_b.wav"),
    "leavewater_c" : preload("res://sfx/leavewater_c.wav"),
    "leavewater_d" : preload("res://sfx/leavewater_d.wav"),
    
    "splash_a" : preload("res://sfx/splash_a.wav"),
    "splash_b" : preload("res://sfx/splash_b.wav"),
    "splash_c" : preload("res://sfx/splash_c.wav"),
    "splash_d" : preload("res://sfx/splash_d.wav"),
    
    "pop" : preload("res://sfx/pop.wav"),
}

class Emitter3D extends AudioStreamPlayer3D:
    var is_ready = false
    var frame_counter = 0

    func emit(parent : Node, sound, arg_position, channel):
        if parent:
            parent.add_child(self)
        else:
            # FIXME: add to a voxel chunk so it moves with the world when the world moves
            DummySingleton.get_tree().get_root().add_child(self)
        transform.origin = arg_position
        
        if false:
            var abs_position = global_transform.origin
            if parent:
                parent.remove_child(self)
            DummySingleton.get_tree().get_root().add_child(self)
            global_transform.origin = abs_position
        
        stream = sound
        bus = channel
        
        attenuation_model = ATTENUATION_INVERSE_DISTANCE
        volume_db = 20
        max_db = 6
        
        attenuation_filter_cutoff_hz = 22000.0
        attenuation_filter_db = -0.001
        
        finished.connect(self.queue_free)
        
        play()
        
        return self


class Emitter extends AudioStreamPlayer:
    var is_ready = false
    var frame_counter = 0

    func emit(parent : Node, sound, channel):
        parent.add_child(self)
        
        stream = sound
        bus = channel
        
        volume_db = -3
        play()
        
        finished.connect(self.queue_free)
        
        return self

func emit(sound, parent = null, arg_position = Vector3(), channel = "SFX"):
    var stream = null
    if sound is String and sound in sounds:
        stream = sounds[sound]
    elif sound is AudioStream:
        stream = sound
    if parent or arg_position != Vector3():
        if !parent:
            parent = get_tree().current_scene
        return Emitter3D.new().emit(parent, stream, arg_position, channel)
    else:
        return Emitter.new().emit(self, stream, channel)
