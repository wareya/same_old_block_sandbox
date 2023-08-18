
global uniform float render_distance;

void decode_custom(vec4 custom, out int d, out int arg_index, out int arg_bitmask)
{
    d = int(custom.r * 255.0);
    int a = int(custom.g * 255.0);
    int b = int(custom.b * 255.0);
    arg_index = ((a << 8) | b);//+70;
    arg_bitmask = int(custom.a * 255.0);
}

#define BIT_00 1
#define BIT_10 2
#define BIT_20 4
#define BIT_01 8
#define BIT_21 16
#define BIT_02 32
#define BIT_12 64
#define BIT_22 128

float estimate_roughness(vec3 color)
{
    float brightness = dot(color, vec3(1.0/3.0));
    float color_v = max(0.0, brightness-0.4)*5.0 + 0.5;
    float color_part = color.b*4.0 + color.g*0.5 - color.r*0.5 + 0.5;
    float f = clamp(color_part - color_v, 0.0, 1.0);
    float roughness = mix(0.5, 1.0, f);
    
    return roughness;
}

void calculate_uv_normal_etc(int d, vec3 pos, inout vec2 uv, inout vec3 normal, inout vec3 tangent, inout vec3 binormal)
{
    binormal = vec3(0.0, -1.0, 0.0);
    if (d == 0)
    {
        uv = vec2(pos.x, pos.z) + vec2(0.5);
        normal = vec3(0.0, 1.0, 0.0);
        tangent = vec3(-1.0, 0.0, 0.0);
        binormal = vec3(0.0, 0.0, 1.0);
    }
    else if (d == 1)
    {
        uv = vec2(-pos.x, pos.z) + vec2(0.5);
        normal = vec3(0.0, -1.0, 0.0);
        tangent = vec3(-1.0, 0.0, 0.0);
        binormal = vec3(0.0, 0.0, -1.0);
    }
    else if (d == 2)
    {
        uv = vec2(-pos.x, -pos.y) + vec2(0.5);
        normal = vec3(0.0, 0.0, -1.0);
        tangent = vec3(1.0, 0.0, 0.0);
    }
    else if (d == 3)
    {
        uv = vec2(pos.x, -pos.y) + vec2(0.5);
        normal = vec3(0.0, 0.0, 1.0);
        tangent = vec3(-1.0, 0.0, 0.0);
    }
    else if (d == 4)
    {
        uv = vec2(pos.z, -pos.y) + vec2(0.5);
        normal = vec3(-1.0, 0.0, 0.0);
        tangent = vec3(0.0, 0.0, -1.0);
    }
    else if (d == 5)
    {
        uv = vec2(-pos.z, -pos.y) + vec2(0.5);
        normal = vec3(1.0, 0.0, 0.0);
        tangent = vec3(0.0, 0.0, 1.0);
    }
    else // mesh
    {
        pos.x = (fract(pos.x + 0.5) - 0.5) / 0.9;
        uv = vec2(pos.x, -pos.y) + vec2(0.5);
        if (d == 6)
            normal = normalize(vec3( 1.0, 0.0, -1.0));
        else if (d == 7)
            normal = normalize(vec3(-1.0, 0.0, -1.0));
        else if (d == 8)
            normal = normalize(vec3(-1.0, 0.0,  1.0));
        else if (d == 9)
            normal = normalize(vec3( 1.0, 0.0,  1.0));
        tangent = cross(normal, binormal);
    }
}

float get_bitmask_offset(vec2 uv, int arg_bitmask)
{
    vec2 quadrant = round(fract(uv));
    float offset = 0.0;
    
    bool ud_offset = false;
    bool lr_offset = false;
    bool di_offset = false;
    int ud_test = 0;
    int lr_test = 0;
    int di_test = 0;
    
    if (quadrant.x < 0.5 && quadrant.y >= 0.5)
    {
        ud_test = BIT_10;
        lr_test = BIT_01;
        di_test = BIT_00;
    }
    else if (quadrant.x >= 0.5 && quadrant.y >= 0.5)
    {
        ud_test = BIT_10;
        lr_test = BIT_21;
        di_test = BIT_20;
    }
    else if (quadrant.x < 0.5 && quadrant.y <0.5)
    {
        ud_test = BIT_12;
        lr_test = BIT_01;
        di_test = BIT_02;
    }
    else if (quadrant.x >= 0.5 && quadrant.y < 0.5)
    {
        ud_test = BIT_12;
        lr_test = BIT_21;
        di_test = BIT_22;
    }
    if ((arg_bitmask & ud_test) == 0)
        ud_offset = true;
    if ((arg_bitmask & lr_test) == 0)
        lr_offset = true;
    if (ud_offset || lr_offset || (arg_bitmask & di_test) == 0)
        di_offset = true;
    
    if (ud_offset && lr_offset)
        offset = 1.0;
    else if (lr_offset)
        offset = 2.0;
    else if (ud_offset)
        offset = 3.0;
    else if (di_offset)
        offset = 4.0;
    
    return offset;
}