extends Node3D

var semaphore = Semaphore.new()

func _ready() -> void:
    var thread = Thread.new()
    thread.start(dispatch)
    semaphore.post()


var mutex = Mutex.new()
var glob = []
func dispatch():
    semaphore.wait()
    
    mutex.lock()
    mutex.unlock()
    
    var a = my_test_func(0)
    var b = my_test_func(1)
    var c = my_test_func(2)
    
    mutex.lock()
    glob = [a, b, c]
    print([a[0].size(), b[0].size(), c[0].size()])
    mutex.unlock()

static var asdf = {1 : null}
static var asdf2 = {5 : null, 6 : null, 7 : null, 8 : null}

static var chunk_size = 16

var cache = PackedByteArray()

func my_test_func(target_type : int):
    print("target type: ", target_type)
    var n = [0].duplicate()
    var is_target = func(type : int) -> bool:
        if n[0] == 0:
            print("target type (in lambda): ", target_type)
        n[0] = 1
        if type == 0:
            return false
        if target_type == 0:
            return not type in asdf and not type in asdf2
        elif target_type == 1:
            return type in asdf
        elif target_type == 2:
            return type in asdf2
        return false
    
    var verts = PackedVector3Array()
    
    for x in chunk_size:
        if is_target.call(x):
            verts.push_back(Vector3(x, 0, 0))
    
    print(verts.size())
    
    var ret = [verts]
    return ret
