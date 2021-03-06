#version 300 es

// This is a fragment shader. If you've opened this file first, please
// open and read lambert.vert.glsl before reading on.
// Unlike the vertex shader, the fragment shader actually does compute
// the shading of geometry. For every pixel in your program's output
// screen, the fragment shader is run for every bit of geometry that
// particular pixel overlaps. By implicitly interpolating the position
// data passed into the fragment shader by the vertex shader, the fragment shader
// can compute what color to apply to its pixel based on things like vertex
// position, light position, and vertex color.
precision highp float;

uniform vec4 u_Color; // The color with which to render this instance of geometry.
uniform vec4 u_Time;
uniform vec2 u_Window;
uniform mat4 u_ViewInv;

// These are the interpolated values out of the rasterizer, so you can't know
// their specific values without knowing the vertices that contributed to them
in vec4 fs_Nor;
in vec4 fs_LightVec;
in vec4 fs_Col;

in vec3 ray_Dir;
in vec3 ray_O;
in vec3 ray_U;
in vec3 ray_R;
in vec4 ws_Pos;

#define M_PI 3.1415926535897932384626433832795

out vec4 out_Col; // This is the final output color that you will see on your
                  // screen for the pixel that is currently being processed.

float contrast_remap(float x) {
    return clamp(x * (x + 0.5) * (x + 0.5) * (x + 0.5), 0.0, 1.0 );
}

float cosine_remap(float x) {
    return (1.0 - cos(x * 3.1415)) / 2.0;
}

float fract_comp(float x) {
    return x - floor(x);
}

float fade (float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); 
}

float lerp(float x0, float x1, float t) {
    return (1.0 - t) * x0 + (t * x1);
}

vec4 mod289(vec4 x)
{
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}
 
vec4 permute(vec4 x)
{
    return mod289(((x*34.0)+1.0)*x);
}

vec3 noise_gen3D(vec3 pos) {
    float x = fract(sin(dot(vec3(pos.x,pos.y,pos.z), vec3(12.9898, 78.233, 78.156))) * 43758.5453);
    float y = fract(sin(dot(vec3(pos.x,pos.y,pos.z), vec3(2.332, 14.5512, 170.112))) * 78458.1093);
    float z = fract(sin(dot(vec3(pos.x,pos.y,pos.z), vec3(400.12, 90.5467, 10.222))) * 90458.7764);
    return 2.0 * (vec3(x,y,z) - 0.5);
}

float dotGridGradient(vec3 grid, vec3 pos) {
    vec3 grad = normalize(noise_gen3D(grid));
    vec3 diff = (pos - grid);
    //return grad.x;
    return clamp(dot(grad,diff),-1.0,1.0);
}

float perlin3D(vec3 pos, float step) {
    pos = pos/step;
    vec3 ming = floor(pos / step) * step;
    ming = floor(pos);
    vec3 maxg = ming + vec3(step, step, step);
    maxg = ming + vec3(1.0);
    vec3 range = maxg - ming;
    vec3 diff = pos - ming;
    vec3 diff2 = maxg - pos;
    float d000 = dotGridGradient(ming, pos);
    float d001 = dotGridGradient(vec3(ming[0], ming[1], maxg[2]), pos);
    float d010 = dotGridGradient(vec3(ming[0], maxg[1], ming[2]), pos);
    float d011 = dotGridGradient(vec3(ming[0], maxg[1], maxg[2]), pos);
    float d111 = dotGridGradient(vec3(maxg[0], maxg[1], maxg[2]), pos);
    float d100 = dotGridGradient(vec3(maxg[0], ming[1], ming[2]), pos);
    float d101 = dotGridGradient(vec3(maxg[0], ming[1], maxg[2]), pos);
    float d110 = dotGridGradient(vec3(maxg[0], maxg[1], ming[2]), pos);

    float ix00 = mix(d000,d100, fade(diff[0]));
    float ix01 = mix(d001,d101, fade(diff[0]));
    float ix10 = mix(d010,d110, fade(diff[0]));
    float ix11 = mix(d011,d111, fade(diff[0]));

    float iy0 = mix(ix00, ix10, fade(diff[1]));
    float iy1 = mix(ix01, ix11, fade(diff[1]));

    float iz = mix(iy0, iy1, fade(diff[2]));

    //return abs(range.x * 9.0);
    return (iz + 1.0) / 2.0;
    //return range.y;
    //return abs(diff.x);
}

mat4 rotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    angle = -angle;
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat4(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,  0.0,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,           0.0,
                0.0,                                0.0,                                0.0,                                1.0);
}

float opS( float d1, float d2 )
{
    
    return max(-d2,d1);
}

vec2 opU( vec2 d1, vec2 d2 )
{
	return (d1.x<d2.x) ? d1 : d2;
}


vec3 opTwist( vec3 p )
{
    float  c = cos(10.0*p.y+10.0);
    float  s = sin(10.0*p.y+10.0);
    mat2   m = mat2(c,-s,s,c);
    return vec3(m*p.xz,p.y);
}

float sdPlane( vec3 p )
{
	return p.y;
}

float sdSphere( vec3 p, float s )
{
    return length(p)-s;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}


float sdTorus( vec3 p, vec2 t )
{
    return length( vec2(length(p.xz)-t.x,p.y) )-t.y;
}

float sdCappedCone(vec3 p, vec3 c )
{
    vec2 q = vec2( length(p.xz), p.y );
    vec2 v = vec2( c.z*c.y/c.x, -c.z );
    vec2 w = v - q;
    vec2 vv = vec2( dot(v,v), v.x*v.x );
    vec2 qv = vec2( dot(v,w), v.x*w.x );
    vec2 d = max(qv,0.0)*qv/vv;
    return sqrt( dot(w,w) - max(d.x,d.y) ) * sign(max(q.y*v.x-q.x*v.y,w.y));
}

float opRep( vec3 p, vec3 c )
{
    vec3 q = mod(p,c)-0.5*c;
    return sdSphere( q , 1.0);
}

vec3 opRt( vec3 p, vec3 axis, float angle )
{
    mat4 m = rotationMatrix(axis,angle);
    vec3 q = vec3(m*vec4(p,1.0));
    return q;
}


vec2 smin( vec2 a, vec2 b, float k )
{
    float h = clamp( 0.5+0.5*(b.x-a.x)/k, 0.0, 1.0 );
    float t = mix( b.x, a.x, h ) - k*h*(1.0-h);
    float m = mix( b.y, a.y, h );
    vec2 ret = vec2(t,m);
    return ret;
}

float intersectSphere(vec3 rd, vec3 r0, vec3 s0, float sr){
    float a = dot(rd, rd);
    vec3 s0_r0 = r0 - s0;
    float b = 2.0 * dot(rd, s0_r0);
    float c = dot(s0_r0, s0_r0) - (sr * sr);
    if (b*b - 4.0*a*c < 0.0) {
        return -1.0;
    }
    return (-b - sqrt((b*b) - 4.0*a*c))/(2.0*a);
}

float nP(float p) {
    return (p + 1.0) /2.0;
}

float la_mult(float v, float scale) {
    return v*scale + (1.0-scale);
}


vec2 sdfMoonPlanet(vec3 pos, vec3 planet_pos, float planet_rad, float bound, float noise_freq) {
    planet_rad *= bound;
    float perlin_scale = bound - planet_rad;
    float perlin_base = perlin3D(pos - planet_pos, planet_rad * noise_freq);
    perlin_base = clamp(perlin_base, 0.0,0.45);

    float perlin2 = perlin3D(pos - planet_pos, planet_rad * 0.1 * noise_freq);
    //perlin2 = 1.0;
    float final_perlin = perlin_base * la_mult(perlin2,0.05);
    //final_perlin = clamp(final_perlin, 0.0 , 0.4);
    return vec2(  sdSphere( pos - planet_pos, planet_rad) - final_perlin * perlin_scale, (final_perlin * 0.5) + 0.5 );
}

// m = 0.5 to 0.6
vec2 sdfEarthPlanet(vec3 pos, vec3 planet_pos, float planet_rad, float bound, float noise_freq) {
    float t = (cos(8.0 * M_PI * u_Time.z / 300.0)  + 1.0 ) / 2.0;
    t = 1.0 - t;
    float m = -1.0;
    planet_rad *= bound;
    float perlin_scale = bound - planet_rad;
    float perlin_base = perlin3D(pos - planet_pos, planet_rad * noise_freq);

    perlin_base *= 1.10;
    perlin_base -= 0.1;
    float perlin3 = perlin3D(pos - planet_pos, planet_rad * 0.3 * noise_freq);
    float perlin_base_capped = min(perlin_base, 0.6);
    perlin_base_capped *= la_mult(perlin3,0.2);
    float sea_level = 0.40;
    float perlin_base_clamp = clamp(perlin_base_capped, sea_level,1.0);
    if(perlin_base_clamp <= sea_level) {
        perlin_base_clamp -= abs(perlin_base_capped - sea_level) * 0.5;
        perlin_base_clamp += perlin3 * 1.5 *abs(perlin_base_clamp - sea_level) * t * perlin_base * 2.0;
    } else {
        perlin_base_clamp += (perlin_base_capped - sea_level) * 0.25;
        perlin_base_clamp -= perlin3 * 1.2 *(perlin_base_clamp - sea_level);
    }
    if(perlin_base > 0.63) {
        perlin_base_clamp -= (perlin_base - 0.63) * 2.0;
        m = 0.581;
    }
    float perlin2 = perlin3D(pos - planet_pos, planet_rad * 0.02 * noise_freq);
    float final_perlin = perlin_base_clamp * la_mult(perlin2, 0.015);
    if(m < 0.0) {m = (final_perlin * 0.1) + 0.5;}
    return vec2(  sdSphere( pos - planet_pos, planet_rad) - final_perlin * perlin_scale, m);
}

vec2 sdfVolcanoPlanet(vec3 pos, vec3 planet_pos, float planet_rad, float bound, float noise_freq) {
    float t = (cos(12.0 * M_PI * u_Time.z / 300.0)  + 1.0 ) / 2.0;
    t = 1.0 - t;
    float m = 0.0;
    planet_rad *= bound;
    float perlin_scale = bound - planet_rad;
    float perlin_base = perlin3D(pos - planet_pos, planet_rad * noise_freq);
    float p2 = abs(perlin_base - 0.5)  * 2.0;
    p2 += 0.05;
    p2 = fade(p2);
    
    float perlin2 = perlin3D(pos - planet_pos, planet_rad * noise_freq * 0.15);
    float p22 = abs(perlin2 - 0.5)  * 2.0;
    p22 = fade(p22);
    float lava = p22;
    p22 = max(0.1,p22);
    if(p22 > 0.30) {
        p22 -= (p22 - 0.30) * 3.0; 
    }
   

    float perlin3 = perlin3D(pos - planet_pos, planet_rad * noise_freq * 0.01);

    float final_perlin = p2 - p22 * 0.1;
    final_perlin = max(0.0,final_perlin);
    if(final_perlin < 0.001) {
        final_perlin -= lava * 0.1 * t * 2.0 * perlin_base;
        final_perlin += perlin3 * 0.005;
        m = lava*0.1 + 0.7;
    }
    if(m <= 0.0) {m = (final_perlin * 0.1) + 0.6;}
    final_perlin *= la_mult(perlin3,0.09);
    vec2 planet = vec2(  sdSphere( pos - planet_pos, planet_rad) - final_perlin * perlin_scale, m);
    return planet;
}

vec2 map_perlin_planet(vec3 pos, vec3 planet_pos, float bound) {
    vec2 res;
    //res = sdfMoonPlanet (pos, planet_pos, 0.5, bound, 0.9);
    if(u_Color.z == 0.0) {
        if(u_Time.x < 1.0) {
            res = sdfEarthPlanet (pos, planet_pos, 0.35, bound, 0.9);
            //res = sdfVolcanoPlanet (pos, planet_pos, 0.8, bound, 0.75);
        } else {
            float p = floor(u_Time.x)/2.0;
            vec3 p3 = noise_gen3D(vec3(p));
            if(p3.x < 0.5) {
                p = p3.z * 0.3 + 0.7;
                float size = p3.y * 0.1 + 0.3;
                res = sdfEarthPlanet (pos, planet_pos, size, bound, p);
            } else {
                p = p3.z * 0.3 + 0.6;
                float size = p3.y * 0.1 + 0.75;
                res = sdfVolcanoPlanet (pos, planet_pos, size, bound, p);
            }
        }
    } else if(u_Color.z == 1.0) {
        res = sdfEarthPlanet (pos, planet_pos, u_Color.x, bound, 1.0/u_Color.y);
    } else {
        res = sdfVolcanoPlanet (pos, planet_pos, u_Color.x + 0.2, bound, 1.0/u_Color.y);
    }
    //res = sdfVolcanoPlanet (pos, planet_pos, 0.35, bound, 0.9);
    return res;
}

vec2 map( vec3 pos)
{
    
    float t = (cos(2.0 *M_PI * u_Time.y / (u_Time.w ) ) + 1.0 ) / 2.0;
    t = 1.0 - t;
    vec3 x_axis = vec3(1,0,0);
    vec3 y_axis = vec3(0,1,0);
    vec3 z_axis = vec3(0,0,1);
    float eater_m = 0.0;
    //vec2 res =  vec2(sdSphere(     pos , 0.5 ), eater_m);
    //  vec2 res = smin( vec2(sdSphere(     pos , 0.5 ), eater_m) ,
    //  vec2(sdSphere(    pos-vec3( 0.0,0.0, 0.3), 0.3 ) , eater_m ) ,0.1);
    
    vec2 res = vec2(opS( sdSphere(     pos , 0.5 ) ,
                     sdSphere(    pos-vec3( 0.0,0.0, 0.3), 0.3 ) ), eater_m);
                     
    
    res = vec2(opS( res.x , sdSphere(    pos-vec3( 0.0,-0.5, 0.1), 0.3 ) ), eater_m);
    res = smin(res , vec2(sdSphere(    pos-vec3( 0.0,0.0, -0.5), 0.3 ), eater_m), 0.1);
    //res = smin(res , vec2(sdTorus(    opRt(pos-vec3( 0.0,-0.35, 0.0),x_axis,M_PI/2.0), vec2(0.3,0.10) ), 1.0), 0.1);
    
    vec2 eyelid1 = vec2(opS( sdSphere(   opRt(pos-vec3( 0.0,0.0, 0.3),x_axis,(t + 0.1)*M_PI/4.0) , 0.3 ) ,
                    sdBox(    opRt(pos-vec3( 0.0, 0.0, 0.3),x_axis,(t + 0.1)*M_PI/4.0)-vec3( 0.0, -0.6, 0.0), vec3(0.6)) ), eater_m);
    vec2 eyelid2 = vec2(opS( sdSphere(   opRt(pos-vec3( 0.0,-0.05, 0.3),x_axis,(t + 0.1)*-M_PI/4.0) , 0.28 ) ,
                    sdBox(    opRt(pos-vec3( 0.0, -0.05, 0.3),x_axis,(t + 0.1)*-M_PI/4.0)-vec3( 0.0, 0.6, 0.0), vec3(0.6)) ), eater_m);

    vec2 mouth_bot = vec2(opS( sdSphere(   opRt(pos-vec3( 0.0,-0.55 - (0.2 * t), 0.1),x_axis,(t + 0.05)*-M_PI/4.0), 0.3 ) ,
                sdBox(    opRt(pos-vec3( 0.0, -0.55, 0.05)-vec3( 0.0,  -(0.2 * t), 0.0),x_axis,(t + 0.05)*-M_PI/4.0) -vec3( 0.0, 0.6, 0.05), vec3(0.6)) ), eater_m);
    mouth_bot = smin(mouth_bot , vec2(sdTorus(    opRt(pos-vec3( 0.0,-0.555 - (0.2 * t), 0.05),x_axis,(t + 0.05)*-M_PI/4.0), vec2(0.3,0.03) ), eater_m), 0.05);
    
    res = smin(res , vec2(sdTorus(opRt(pos-vec3( 0.0,-0.3 , 0.1),x_axis,0.0), vec2(0.27,0.03) ), eater_m) , 0.05);
    res = smin(res,mouth_bot,0.1);
    vec2 mouth_back = vec2(opS( sdSphere(   opRt(pos-vec3( 0.0,-0.35 - (0.1 * t), 0.0),x_axis,0.0) , 0.33 ) ,
    sdBox(    opRt(pos-vec3( 0.0, -0.4, 0.0),x_axis,0.0)-vec3( 0.0, 0.0, 1.0), vec3(1.0)) ), eater_m );

    res = smin(res , mouth_back, 0.1);
    res = opU(res,eyelid1);
    res = opU(res,eyelid2);
    //vec2 eye_ball = vec2(opS(sdSphere(pos - vec3(0.0,0.0,0.275), 0.295), sdSphere(pos - vec3(0.0,0.0,0.525), 0.08) ), 2.0 );

    vec2 eye_ball = opU( vec2(sdSphere(pos - vec3(0.0,0.0,0.275), 0.295), 0.1 )  , vec2(sdSphere(pos - vec3(0.0,- 0.025,0.55), 0.05), 0.2 ) );

    res = opU(res,eye_ball);
    
    //res = opU(res, vec2(sdTorus( opRt(pos-vec3(0.0,0.0,0.4),vec3(1,0,0), M_PI/2.0 ), vec2(0.25,0.05)), 0.5) );
    //res = vec2(opRep(vec3(1,1,1),vec3(1,1,1)),1.0);
    return res;
}

vec3 calcNormal(vec3 pos )
{
    vec2 e = vec2(1.0,-1.0)*0.5773*0.0005;
    return normalize( e.xyy*map( pos + e.xyy).x + 
					  e.yyx*map( pos + e.yyx).x + 
					  e.yxy*map( pos + e.yxy).x + 
					  e.xxx*map( pos + e.xxx).x );
}

vec3 calcPerlinPlanetNorm(vec3 pos, vec3 planet_pos, float bound)
{
    vec2 e = vec2(1.0,-1.0)*0.5773*0.0005;
    return normalize( e.xyy*map_perlin_planet( pos + e.xyy , planet_pos, bound).x + 
					  e.yyx*map_perlin_planet( pos + e.yyx , planet_pos, bound).x + 
					  e.yxy*map_perlin_planet( pos + e.yxy , planet_pos, bound).x + 
					  e.xxx*map_perlin_planet( pos + e.xxx , planet_pos, bound).x );
}

struct Mat
{
    vec4 diffuseColor;
    float diffuseTerm;
    float specularTerm;
    vec3 specularColor;
};

Mat getMaterial(float m, vec4 norm, vec3 ray_Dir) {
    Mat mat;
    vec4 H = normalize(fs_LightVec + vec4(ray_Dir,0.0));
    mat.specularTerm = pow(clamp(dot(H,norm),0.0,1.0 ),10.0);
    mat.diffuseColor = vec4(1.0);
    if(m >= 0.5 && m < 0.6 ) {
        //PLANET COLORS INTERP
        float nm = (m - 0.5) * 10.0;
        if(nm < 0.40) {
            vec3 col = mix(vec3(0.0,0.0,0.1), vec3(0.0,0.2,1.0), (nm * 2.5) - 0.4) ;
            mat.diffuseColor = vec4(col,1.0);
        } else if (m < 0.581) {
            vec3 col = mix(vec3(0.2,0.5,0.1), vec3(1.0,0.8,0.2), (nm - 0.3) * 3.5 ) ;
            mat.diffuseColor = vec4(col,1.0);
            mat.specularTerm = 0.0;
        } else {
            vec3 col = mix(vec3(0.2,0.5,0.1), vec3(1.0,0.8,0.2), (nm - 0.3) * 3.5 ) ;
            col = vec3(0.4,0.1,0.0);
            mat.diffuseColor = vec4(col,1.0);
        }
    } else if (m >= 0.6 && m < 0.7) {

        float nm = (m - 0.6) * 10.0;
        if(nm < 0.001) {
            vec3 col = vec3(0.4,0.1,0.0);
            mat.diffuseColor = vec4(col,1.0);
        }else if(nm < 0.005) {
            vec3 col = mix(vec3(1,0,0), vec3(0.6), fade(nm/0.005) ) ;
            mat.diffuseColor = vec4(col,1.0);
        } else if(nm < 0.01) {
            vec3 col = mix(vec3(0.6), vec3(0,0.3,0.3), fade ((nm - 0.005)/0.005)) ;
            mat.diffuseColor = vec4(col,1.0);
        } else {
            vec3 col = mix(vec3(0.1,0.1,0.02), vec3(0.0,0.1,0.3), nm) ;
            mat.diffuseColor = vec4(col,1.0);
        }
    } else if (m >= 0.7 && m < 0.8) {
        float nm = (m - 0.7) * 10.0;
        vec3 col = mix(vec3(0.4,0.1,0.0) * 0.5, vec3(0.4,0.1,0.0), nm + 0.3) ;
        mat.diffuseColor = vec4(col,1.0);
    }
    if(m < 0.5) {
        mat.diffuseColor = mix(vec4(0.8,0.4,0.4,1),vec4(1,1,1,1) , m * 10.0);
        if(m >= 0.2) {
            mat.diffuseColor = mix(vec4(0.0,0.0,0.0,1.0),vec4(1,1,1,1) , (m - 0.2) * 10.0);
        }
        if (m < 0.01) {
            mat.specularTerm /= 2.0;
        }
    }
    mat.diffuseTerm = dot(normalize(norm), normalize(fs_LightVec));
    mat.specularColor = vec3(0.8);
    return mat;
}

void main()
{
    // Material base color (before shading)

    float u = gl_FragCoord.x * 2.0 / u_Window.x - 1.0;
    float v = gl_FragCoord.y * 2.0 / u_Window.y - 1.0;

    float imageWidth = u_Window.x;
    float imageHeight = u_Window.y;
    float imageAspectRatio = imageWidth / imageHeight; // assuming width > height 
    float fov = 45.0;
    float Px = (u) * tan(fov / 2.0 * M_PI / 180.0) * imageAspectRatio; 
    float Py = (v) * tan(fov / 2.0 * M_PI / 180.0);
    vec3 ray_O = vec3(0.0); 
    vec3 ray_Dir = vec3(Px, Py, -1) - ray_O;
    ray_Dir = normalize(ray_Dir);
    

    ray_O = vec3(u_ViewInv * vec4(ray_O , 1.0));
    ray_Dir = vec3(u_ViewInv * vec4(ray_Dir, 0.0));
    ray_Dir = normalize(ray_Dir);
    
    vec4 diffuseColor = vec4(0,0.07,0.1,1.0);
    vec4 norm;
        //diffuseColor = vec4(ws_Pos);

        // Calculate the diffuse term for Lambert shading
    float diffuseTerm = dot(normalize(fs_Nor), normalize(fs_LightVec));
    float specularTerm = 0.0;
    diffuseTerm = 1.0;

        // ray marching step
        float step = 0.0;
        int count = 0;
        vec3 P = ray_O;
        //Simple raymarching (lots of assumptions made / hardcoding)
        bool flag = true;

        float tp = 1000.0;
        float time = (cos(2.0 * M_PI * u_Time.y / (u_Time.w*2.0))  + 1.0 ) / 2.0;
        vec3 planet_pos = mix(vec3(0.2,-0.9,2.0),vec3(0.0,-0.4,-0.2), 1.0 - time );
        float sphere_bound = 0.2;
        float tsphere = intersectSphere(ray_Dir, ray_O, planet_pos, sphere_bound);
        if(tsphere > 0.0) {
        tp = tsphere;
            while (flag) {
                P = ray_O + tp * ray_Dir;
                vec2 map = map_perlin_planet(P, planet_pos, sphere_bound);
                float d = map.x;
                if(abs(d) < 0.001) {
                    
                    diffuseColor = mix(vec4(1,0,0,1),vec4(0,0,1,1) ,1.0);
                    float m = map.y;
                    norm = vec4(calcPerlinPlanetNorm(P,planet_pos, sphere_bound), 0.0);
                    Mat mat = getMaterial(m,norm,ray_Dir);
                    specularTerm = mat.specularTerm;
                    diffuseColor = mat.diffuseColor;
                    diffuseTerm = mat.diffuseTerm;
                    
                    flag = false;
                } 
                tp += d/2.0;
                
                if(count > 64 || tp > 8.0) {
                    //diffuseColor = vec4(1.0);
                    //diffuseTerm = 1.0;
                    tp = 1000.0;
                    flag = false;
                }
                count++;
            }
        // diffuseColor = vec4(1.0);
        // tp = 0.0;
        }
        step = 0.0;
        count = 0;
        flag = true;
        float t = 0.0;

    //ray intersection test planet

        while (flag) {
            float radius = 0.5;
            P = ray_O + t * ray_Dir;
            vec2 map = map(P);
            float d = map.x;
            if(abs(d) < 0.005 && t < tp) {
                norm = vec4(calcNormal(P),0.0 );
                float m = map.y;
                Mat mat = getMaterial(m,norm,ray_Dir);
                specularTerm = mat.specularTerm;
                diffuseColor = mat.diffuseColor;
                diffuseTerm = mat.diffuseTerm;
                
                flag = false;
            } 
            t += d;
            if(count > 126 || t > 200.0) {
                flag = false;
            }
            count++;
        }

        float ambientTerm = 0.2;

        float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                            //to simulate ambient lighting. This ensures that faces that are not
                                                            //lit by our point light are not completely black.
        lightIntensity = clamp(lightIntensity, 0.2,1.0);
        //lightIntensity = 1.0f;
        // Compute final shaded color
        //vec2 window = (u_Window.x, u_Window.y);
        vec3 specularCol = vec3(0.8);
        out_Col = vec4(diffuseColor.rgb * lightIntensity, 1.0) +specularTerm * vec4(specularCol,0.0);
}
