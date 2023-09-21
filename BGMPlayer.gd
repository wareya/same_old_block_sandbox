extends AudioStreamPlayer

const music_playlist = [
    preload("res://bgm/main theme.ogg"),
    preload("res://bgm/cold theme.ogg"),
    preload("res://bgm/hot theme.ogg"),
]
var music_cursor = 0
func start_music_playlist():
    while true:
        await get_tree().create_timer(1.0).timeout
        var next = music_playlist[music_cursor]
        music_cursor = (music_cursor+1)%music_playlist.size()
        stream = next
        if !playing:
            playing = true
        await finished
    
