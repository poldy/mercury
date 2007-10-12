%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1997, 2003-2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File: mogl.m.
% Main authors: conway, juliensf.
% 
% This file provides a binding to OpenGL 1.1. (It won't work with OpenGL 1.0.)
%
% It will work with OpenGL 1.2 - 1.5 but it doesn't (currently)
% implement any of the extended functionality in those versions.
%
% TODO:
%   - finish texture mapping stuff
%   - finish pixel rectangle stuff
%   - vertex arrays
%   - 2d evaluators
%   - various state queries
%   - stuff from later versions of OpenGL
%   - break this module up into submodules
%   - document all this ;)
%
%------------------------------------------------------------------------------%

:- module mogl.
:- interface.

:- include_module mogl.type_tables.

:- import_module bitmap.
:- import_module bool.
:- import_module float.
:- import_module int.
:- import_module io.
:- import_module list.
:- import_module maybe.

%------------------------------------------------------------------------------%
%
% GL errors
%

:- type mogl.error  
    --->    no_error
    ;       invalid_enum
    ;       invalid_value
    ;       invalid_operation
    ;       stack_overflow
    ;       stack_underflow
    ;       out_of_memory.

:- pred get_error(mogl.error::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Begin/End objects
%

:- type block_mode  
    --->    points
    ;       line_strip
    ;       line_loop
    ;       lines
    ;       polygon
    ;       triangle_strip
    ;       triangle_fan
    ;       triangles
    ;       quad_strip
    ;       quads.

:- pred begin(block_mode::in, io::di, io::uo) is det.

:- pred end(io::di, io::uo) is det.

:- pred edge_flag(bool::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Vertex specification
%

:- pred vertex2(float::in, float::in, io::di, io::uo) is det.

:- pred vertex3(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred vertex4(float::in, float::in, float::in, float::in, io::di, io::uo)
    is det.

:- pred rect(float::in, float::in, float::in, float::in, io::di, io::uo)
    is det.

:- pred tex_coord1(float::in, io::di, io::uo) is det.

:- pred tex_coord2(float::in, float::in, io::di, io::uo) is det.

:- pred tex_coord3(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred tex_coord4(float::in, float::in, float::in, float::in, io::di, io::uo)
    is det.

:- pred normal3(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred color3(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred color4(float::in, float::in, float::in, float::in, io::di, io::uo)
    is det.

:- pred index(float::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Coordinate transformations
%

:- pred depth_range(float::in, float::in, io::di, io::uo) is det.

:- pred viewport(int::in, int::in, int::in, int::in, io::di, io::uo) is det.

:- type matrix_mode
    --->    texture
    ;       modelview
    ;       projection.

:- type matrix
    --->    m(float, float, float, float,   % a[11], a[12], ...
              float, float, float, float,   % a[21], a[22], ...
              float, float, float, float,   % a[31], a[32], ...
              float, float, float, float).  % a[41], a[42], ...

:- pred matrix_mode(matrix_mode::in, io::di, io::uo) is det.

:- pred get_matrix_mode(matrix_mode::out, io::di, io::uo) is det.

:- pred load_matrix(matrix::in, io::di, io::uo) is det.

:- pred mult_matrix(matrix::in, io::di, io::uo) is det.

:- pred load_identity(io::di, io::uo) is det.

:- pred rotate(float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.

:- pred translate(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred scale(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred frustum(float::in, float::in, float::in, float::in, float::in,
    float::in, io::di, io::uo) is det.

:- pred ortho(float::in, float::in, float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.

:- pred push_matrix(io::di, io::uo) is det.

:- pred pop_matrix(io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Clipping
%

:- type clip_plane
    --->    clip(
                clip_x :: float, 
                clip_y :: float, 
                clip_z :: float, 
                clip_w :: float
            ).

:- pred clip_plane(int::in, clip_plane::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Current raster position
%

:- pred raster_pos2(float::in, float::in, io::di, io::uo) is det.

:- pred raster_pos3(float::in, float::in, float::in, io::di, io::uo) is det.

:- pred raster_pos4(float::in, float::in, float::in, float::in, io::di,
    io::uo) is det.

%------------------------------------------------------------------------------%
%
% Colors and coloring
%

:- type face_direction ---> cw ; ccw.

:- type face_side
    --->    front 
    ;       back 
    ;       front_and_back.

:- type material
    --->    ambient(float, float, float, float)
    ;       diffuse(float, float, float, float)
    ;       ambient_and_diffuse(float, float, float, float)
    ;       specular(float, float, float, float)
    ;       emission(float, float, float, float)
    ;       shininess(float)
    ;       color_indexes(float, float, float).

:- type light_no == int.

:- type light
    --->    ambient(float, float, float, float)
    ;       diffuse(float, float, float, float)
    ;       specular(float, float, float, float)
    ;       position(float, float, float, float)
    ;       spot_direction(float, float, float)
    ;       spot_exponent(float)
    ;       spot_cutoff(float)
    ;       constant_attenuation(float)
    ;       linear_attenuation(float)
    ;       quadratic_attenuation(float).

:- type lighting_model
    --->    light_model_ambient(float, float, float, float)
    ;       light_model_local_viewer(bool)
    ;       light_model_two_side(bool).

:- type color_material_mode
    --->    ambient
    ;       diffuse
    ;       ambient_and_diffuse
    ;       specular
    ;       emission.

:- type shade_model
    --->    smooth
    ;       flat.

:- pred front_face(face_direction::in, io::di, io::uo) is det.

:- pred material(face_side::in, material::in, io::di, io::uo) is det.

:- pred light(light_no::in, light::in, io::di, io::uo) is det.

:- pred light_model(lighting_model::in, io::di, io::uo) is det.

:- pred color_material(face_side::in, color_material_mode::in,
    io::di, io::uo) is det.

:- pred shade_model(shade_model::in, io::di, io::uo) is det.

:- pred get_shade_model(shade_model::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Points
%

:- pred point_size(float::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Line segments
%

:- pred line_width(float::in, io::di, io::uo) is det.

:- pred line_stipple(int::in, int::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Polygons
%

:- type polygon_stipple == bitmap.

:- type polygon_mode
    --->    point
    ;       line
    ;       fill.

:- pred cull_face(face_side::in, io::di, io::uo) is det.

:- pred polygon_stipple(polygon_stipple::bitmap_ui, io::di, io::uo) is det.

:- pred polygon_mode(face_side::in, polygon_mode::in, io::di, io::uo) is det.

:- pred polygon_offset(float::in, float::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Pixel rectangles
%

:- type pixel_store_parameter
    --->    pack_swap_bytes(bool)
    ;       pack_lsb_first(bool)
    ;       pack_row_length(int)
    ;       pack_image_height(int)
    ;       pack_skip_rows(int)
    ;       pack_skip_pixels(int)
    ;       pack_skip_images(int)
    ;       pack_alignment(int)
    ;       unpack_swap_bytes(bool)
    ;       unpack_lsb_first(bool)
    ;       unpack_row_length(int)
    ;       unpack_image_height(int)
    ;       unpack_skip_rows(int)
    ;       unpack_skip_pixels(int)
    ;       unpack_skip_images(int)
    ;       unpack_alignment(int).

:- pred pixel_store(pixel_store_parameter::in, io::di, io::uo) is det.

:- pred pixel_zoom(float::in, float::in, io::di, io::uo) is det.
    
:- type pixel_transfer_mode
    --->    map_color(bool)
    ;       map_stencil(bool)
    ;       index_shift(int)
    ;       index_offset(int)
    ;       red_scale(float)
    ;       green_scale(float)
    ;       blue_scale(float)
    ;       alpha_scale(float)
    ;       red_bias(float)
    ;       green_bias(float)
    ;       blue_bias(float)
    ;       alpha_bias(float)
    ;       depth_bias(float).

:- pred pixel_transfer(pixel_transfer_mode::in, io::di, io::uo) is det.

:- type copy_type
    --->    color
    ;       stencil
    ;       depth.

:- pred copy_pixels(int::in, int::in, int::in, int::in, copy_type::in, 
    io::di, io::uo) is det.

:- type pixel_format
    --->    color_index
    ;       stencil_index
    ;       depth_component
    ;       red
    ;       green
    ;       blue
    ;       alpha
    ;       rgb
    ;       rgba
    ;       luminance
    ;       luminance_alpha.

:- inst pixel_format_non_stencil_or_depth
    --->    color_index
    ;       red
    ;       green
    ;       blue
    ;       alpha
    ;       rgb
    ;       rgba
    ;       luminance
    ;       luminance_alpha.

:- type pixel_type
    --->    unsigned_byte
    ;       bitmap
    ;       byte
    ;       unsigned_short
    ;       unsigned_int
    ;       int
    ;       float.

:- type read_buffer
    --->    front_left
    ;       front_right
    ;       back_left
    ;       back_right
    ;       front
    ;       back
    ;       left
    ;       right
    ;       front_and_back
    ;       aux(int).

:- pred read_buffer(read_buffer::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Bitmaps
%

:- pred mogl.bitmap(int::in, int::in, float::in, float::in,
    float::in, float::in, bitmap::bitmap_ui, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Texture mapping
%

:- type texture_target
    --->    texture_1d
    ;       proxy_texture_1d        
    ;       texture_2d
    ;       proxy_texture_2d.

:- inst texture_1d ---> texture_1d ; proxy_texture_1d.
:- inst texture_2d ---> texture_2d ; proxy_texture_2d.
% :- inst texture_3d ---> texture_3d ; proxy_texture_3d.

:- inst non_proxy_texture_target ---> texture_1d ; texture_2d.

:- type texture_format
   
    %
    % Base formats.
    %
    
    --->    alpha
    ;       luminance
    ;       luminance_alpha
    ;       intensity
    ;       rgb
    ;       rgba

    %
    % Sized formats.
    %
    
    ;       alpha4
    ;       alpha8
    ;       alpha12
    ;       alpha16
    ;       luminance4
    ;       luminance8
    ;       luminance12
    ;       luminance16
    ;       luminance4_alpha4
    ;       luminance6_alpha2
    ;       luminance8_alpha8
    ;       luminance12_alpha4
    ;       luminance12_alpha12
    ;       luminance16_alpha16
    ;       intensity4
    ;       intensity8
    ;       intensity12
    ;       intensity16
    ;       r3_g3_b2
    ;       rgb4
    ;       rgb5
    ;       rgb10
    ;       rgb12
    ;       rgb16
    ;       rgba2
    ;       rgba4
    ;       rgb5_a1
    ;       rgba8
    ;       rgb10_a2
    ;       rgba12
    ;       rgba16.

:- type texture_parameter
    --->    wrap_s(wrap_mode)
    ;       wrap_t(wrap_mode)
    ;       min_filter(min_filter_method)
    ;       mag_filter(mag_filter_method)
    ;       border_color(float, float, float, float)
    ;       priority(float).

:- type wrap_mode
    --->    clamp
    ;       repeat.

:- type min_filter_method
    --->    nearest
    ;       linear
    ;       nearest_mipmap_nearest
    ;       nearest_mipmap_linear
    ;       linear_mipmap_nearest
    ;       linear_mipmap_linear.

:- type mag_filter_method
    --->    nearest
    ;       linear.

:- pred tex_parameter(texture_target::in(non_proxy_texture_target),
    texture_parameter::in, io::di, io::uo) is det.

    % XXX We should consider making this type abstract.
    %
:- type texture_name == int.

:- pred bind_texture(texture_target::in(non_proxy_texture_target),
    texture_name::in, io::di, io::uo) is det.

:- pred delete_textures(list(texture_name)::in, io::di, io::uo) is det.

:- pred gen_textures(int::in, list(texture_name)::out, io::di, io::uo) is det.

:- pred is_texture(texture_name::in, bool::out, io::di, io::uo) is det.

:- type texture_env_target ---> texture_env.

:- type texture_function 
    --->    decal
    ;       replace
    ;       modulate
    ;       blend.

:- type texture_env_parameter 
    --->    texture_env_mode(texture_function)
    ;       texture_env_color(float, float, float, float).

:- pred tex_env(texture_env_target::in, texture_env_parameter::in,
    io::di, io::uo) is det.

:- type texture_coord ---> s ; t ; r ; q.

:- type texture_gen_parameter
    --->    texture_gen_mode(texture_gen_function)
    ;       object_plane(float, float, float, float)
    ;       eye_plane(float, float, float, float).

:- type texture_gen_function
    --->    object_linear
    ;       eye_linear
    ;       sphere_map.

:- pred tex_gen(texture_coord::in, texture_gen_parameter::in,
    io::di, io::uo) is det.

:- inst border ---> 0 ; 1.

:- type pixel_data == bitmap.

:- pred tex_image_1d(texture_target::in(texture_1d), int::in,
    texture_format::in, int::in, int::in(border),
    pixel_format::in(pixel_format_non_stencil_or_depth),
    pixel_type::in, pixel_data::bitmap_ui, io::di, io::uo) is det.

:- pred tex_image_2d(texture_target::in(texture_2d), int::in,
    texture_format::in, int::in, int::in, int::in(border),
    pixel_format::in(pixel_format_non_stencil_or_depth),
    pixel_type::in, pixel_data::bitmap_ui, io::di, io::uo) is det.

% Requires OpenGL 1.2
% :- pred tex_image_3d(texture_target::in(texture_3d), int::in,
%     texture_format::in, int::in, int::in, int::in, int::in(border),
%     pixel_format::in(pixel_format_non_stencil_or_depth),
%     pixel_type::in, pixel_data::bitmap_ui, io::di, io::uo) is det.

:- pred copy_tex_image_1d(texture_target::in(bound(texture_1d)), int::in,
    texture_format::in, int::in, int::in, int::in, int::in(border),
    io::di, io::uo) is det.

:- pred copy_tex_image_2d(texture_target::in(bound(texture_2d)), int::in,
    texture_format::in, int::in, int::in, int::in, int::in, int::in(border),
    io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Fog
%

:- type fog_parameter
    --->    fog_mode(fog_mode)
    ;       fog_density(float)
    ;       fog_start(float)
    ;       fog_end(float)
    ;       fog_index(float)
    ;       fog_color(float, float, float, float).

:- type fog_mode
    --->    linear
    ;       exp
    ;       exp2.

:- pred fog(fog_parameter::in, io::di, io::uo) is det.

:- pred get_fog_mode(fog_mode::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Per-fragment operations
%

:- pred scissor(int::in, int::in, int::in, int::in, io::di, io::uo) is det.

:- type test_func
    --->    never
    ;       always
    ;       less
    ;       lequal
    ;       equal
    ;       gequal
    ;       greater
    ;       not_equal.

:- pred alpha_func(test_func::in, float::in, io::di, io::uo) is det.

:- pred stencil_func(test_func::in, float::in, int::in, io::di, io::uo)
    is det.

:- type stencil_op
    --->    keep
    ;       zero
    ;       replace
    ;       incr
    ;       decr
    ;       invert.

:- pred stencil_op(stencil_op::in, stencil_op::in, stencil_op::in,
    io::di, io::uo) is det.

:- pred depth_func(test_func::in, io::di, io::uo) is det.

:- type blend_src
    --->    zero
    ;       one
    ;       dst_color
    ;       one_minus_dst_color
    ;       src_alpha
    ;       one_minus_src_alpha
    ;       dst_alpha
    ;       one_minus_dst_alpha
    ;       src_alpha_saturate.

:- type blend_dst
    --->    zero
    ;       one
    ;       src_color
    ;       one_minus_src_color
    ;       src_alpha
    ;       one_minus_src_alpha
    ;       dst_alpha
    ;       one_minus_dst_alpha.

:- pred blend_func(blend_src::in, blend_dst::in, io::di, io::uo) is det.

:- type logic_op
    --->    clear
    ;       (and)
    ;       and_reverse
    ;       copy
    ;       and_inverted
    ;       no_op
    ;       xor
    ;       (or)
    ;       nor
    ;       equiv
    ;       invert
    ;       or_reverse
    ;       copy_inverted
    ;       or_inverted
    ;       nand
    ;       set.

:- pred logic_op(logic_op::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Whole framebuffer operations
%

:- type draw_buffer
    --->    none
    ;       front_left
    ;       front_right
    ;       back_left
    ;       back_right
    ;       front
    ;       back
    ;       left
    ;       right
    ;       front_and_back
    ;       aux(int).

:- pred draw_buffer(draw_buffer::in, io::di, io::uo) is det.

:- pred index_mask(int::in, io::di, io::uo) is det.

:- pred color_mask(bool::in, bool::in, bool::in, bool::in, io::di, io::uo)
    is det.

:- pred depth_mask(bool::in, io::di, io::uo) is det.

:- pred stencil_mask(int::in, io::di, io::uo) is det.

:- type buffer_bit
    --->    color
    ;       depth
    ;       stencil
    ;       accum.

:- pred clear(list(buffer_bit)::in, io::di, io::uo) is det.

:- pred clear_color(float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.

:- pred clear_index(float::in, io::di, io::uo) is det.

:- pred clear_depth(float::in, io::di, io::uo) is det.

:- pred clear_stencil(int::in, io::di, io::uo) is det.

:- pred clear_accum(float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.

:- type accum_op
    --->    accum
    ;       load
    ;       return
    ;       mult
    ;       add.

:- pred accum(accum_op::in, float::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Evaluators
%

:- type control_points(One, Two, Three, Four)
    --->    one(One)        % Control points that have 1 dimension.
    ;       two(Two)        % Control points that have 2 dimensions.
    ;       three(Three)    % Control points have have 3 dimensions.
    ;       four(Four).     % Control points have have 4 dimensions.

    % 1D control points are just lists containing tuples
    % of the appropriate number of values.
    %
:- type control_points_1d == control_points(list(float),
        list({float, float}),
        list({float, float, float}),
        list({float, float, float, float})
    ).

:- type eval_target
    --->    vertex_3
    ;       vertex_4
    ;       index
    ;       color_4
    ;       normal
    ;       texture_coord_1
    ;       texture_coord_2
    ;       texture_coord_3
    ;       texture_coord_4.

:- type curve_points.

:- func make_curve(control_points_1d) = curve_points.

    % This version performs a runtime check to make sure that
    % the evaluator target is compatible with the control points
    % supplied.  It throws an exception if the evaluator target
    % is not compatible with the control points.
    %
:- pred map1(eval_target::in, float::in, float::in, curve_points::in,
    io::di, io::uo) is det.

    % This version does not perform the runtime check above.
    %
:- pred unsafe_map1(eval_target::in, float::in, float::in,
    curve_points::in, io::di, io::uo) is det.

    % This version does not perform the runtime check above
    % and allows you to override the `stride' and `order'
    % parameters.
    %
:- pred unsafe_map1(eval_target::in, float::in, float::in, 
    maybe(int)::in, maybe(int)::in, curve_points::in,
    io::di, io::uo) is det.

:- pred eval_coord1(float::in, io::di, io::uo) is det.

:- type mesh_mode
    --->    point
    ;       line
    ;       fill.

:- inst mesh_mode_1d
    --->    point
    ;       line.

:- pred eval_mesh1(mesh_mode::in(mesh_mode_1d), int::in, int::in,
    io::di, io::uo) is det.

:- pred map_grid1(int::in, float::in, float::in, io::di, io::uo) is det.

:- pred eval_point1(int::in, io::di, io::uo) is det.

    % 2D control points are lists of lists of tuples of the
    % appropriate size.  All the inner lists must have the
    % same length.
    %
:- type control_points_2d == control_points(list(list(float)),
        list(list({float, float})),
        list(list({float, float, float})),
        list(list({float, float, float, float}))
    ).

:- type surface_points.

    % XXX NYI.
    %
% :- func make_surface(control_points_2d) = surface_points.

    % XXX NYI.
    %
% :- pred map2(surface, float::in, float::in, float::in, float::in,
%   io:di, io::uo) is det.

:- pred eval_coord2(float::in, float::in, io::di, io::uo) is det.

:- pred eval_mesh2(mesh_mode::in, int::in, int::in, int::in, int::in,
    io::di, io::uo) is det.

:- pred map_grid2(int::in, float::in, float::in, int::in, float::in,
    float::in, io::di, io::uo) is det.

:- pred eval_point2(int::in, int::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Feedback
%

:- pred pass_through(float::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Selection
%

:- pred init_names(io::di, io::uo) is det.

:- pred pop_name(io::di, io::uo) is det.

:- pred push_name(int::in, io::di, io::uo) is det.

:- pred load_name(int::in, io::di, io::uo) is det.

:- type render_mode
    --->    render
    ;       select
    ;       feedback.

:- pred render_mode(render_mode::in, int::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Display lists
%

:- type display_list_mode 
    --->    compile
    ;       compile_and_execute.

:- pred new_list(int::in, display_list_mode::in, io::di, io::uo) is det.

:- pred end_list(io::di, io::uo) is det.

:- pred call_list(int::in, io::di, io::uo) is det.

:- pred gen_lists(int::in, int::out, io::di, io::uo) is det.

:- pred delete_lists(int::in, int::in, io::di, io::uo) is det.

:- pred is_list(int::in, bool::out, io::di, io::uo) is det.

:- pred list_base(int::in, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Flush and finish
%

:- pred flush(io::di, io::uo) is det.

:- pred finish(io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Enable/Disable
%

:- type control_flag
    --->    alpha_test
    ;       auto_normal
    ;       blend
    ;       clip_plane(int)
    ;       color_logic_op
    ;       color_material
    ;       cull_face
    ;       depth_test
    ;       dither
    ;       fog
    ;       index_logic_op
    ;       light(int)
    ;       lighting
    ;       line_smooth
    ;       line_stipple
    ;       normalize
    ;       point_smooth
    ;       polygon_offset_fill
    ;       polygon_offset_line
    ;       polygon_offset_point
    ;       polygon_stipple
    ;       scissor_test
    ;       stencil_test
    ;       texture_1d
    ;       texture_2d

    %
    % 1D evaluator control flags
    %

    ;   map1_vertex_3
    ;   map1_vertex_4
    ;   map1_index
    ;   map1_color_4
    ;   map1_normal
    ;   map1_texture_coord_1
    ;   map1_texture_coord_2
    ;   map1_texture_coord_3
    ;   map1_texture_coord_4

    %
    % 2D evaluator control flags
    %

    ;   map2_vertex_3
    ;   map2_vertex_4
    ;   map2_index
    ;   map2_color_4
    ;   map2_normal
    ;   map2_texture_coord_1
    ;   map2_texture_coord_2
    ;   map2_texture_coord_3
    ;   map2_texture_coord_4.   
    

:- pred enable(control_flag::in, io::di, io::uo) is det.

:- pred disable(control_flag::in, io::di, io::uo) is det.

:- pred is_enabled(control_flag::in, bool::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Hints
%

:- type hint_target
    --->    perspective_correction
    ;       point_smooth
    ;       line_smooth
    ;       polygon_smooth
    ;       fog.

:- type hint_mode
    --->    fastest
    ;       nicest
    ;       do_not_care.

:- pred hint(hint_target::in, hint_mode::in, io::di, io::uo) is det.

:- pred get_hint(hint_target::in, hint_mode::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% State and state requests
%

:- pred get_clip_plane(int::in, clip_plane::out, io::di, io::uo) is det.

:- type single_boolean_state
    --->    current_raster_position_valid
    ;       depth_writemask
    ;       double_buffer
    ;       edge_flag
    ;       index_mode
    ;       light_model_local_viewer
    ;       light_model_two_side
    ;       map_color
    ;       map_stencil
    ;       pack_lsb_first
    ;       pack_swap_bytes
    ;       rgba_mode
    ;       stereo
    ;       unpack_lsb_first
    ;       unpack_swap_bytes.

:- type quad_boolean_state ---> color_writemask.

:- pred get_boolean(single_boolean_state::in, bool::out, io::di, io::uo)
    is det.

:- pred get_boolean(quad_boolean_state::in,
    bool::out, bool::out, bool::out, bool::out, io::di, io::uo) is det.

:- type single_integer_state
    --->    accum_alpha_bits
    ;       accum_blue_bits
    ;       accum_green_bits
    ;       accum_red_bits
    ;       alpha_bits
    ;       alpha_test_ref
    ;       attrib_stack_depth
    ;       aux_buffers
    ;       blue_bits
    ;       client_attrib_stack_depth
    ;       color_array_size
    ;       color_array_stride
    ;       depth_bits
    ;       depth_clear_value
    ;       edge_flag_array_stride
    ;       feedback_buffer_size
    ;       green_bits
    ;       index_array_stride
    ;       index_bits
    ;       index_offset
    ;       index_shift
    ;       line_stipple_repeat
    ;       list_base
    ;       list_index
    ;       max_attrib_stack_depth
    ;       max_client_attrib_stack_depth
    ;       max_clip_planes
    ;       max_eval_order
    ;       max_lights
    ;       max_list_nesting
    ;       max_modelview_stack_depth
    ;       max_name_stack_depth
    ;       max_pixel_map_table
    ;       max_projection_stack_depth
    ;       max_texture_size
    ;       max_texture_stack_depth
    ;       modelview_stack_depth
    ;       name_stack_depth
    ;       normal_array_stride
    ;       pack_alignment
    ;       pack_row_length
    ;       pack_skip_rows
    ;       projection_stack_depth
    ;       red_bits
    ;       selection_buffer_size
    ;       stencil_bits
    ;       stencil_clear_value
    ;       stencil_ref
    ;       subpixel_bits
    ;       texture_coord_array_size
    ;       texture_coord_array_stride
    ;       texture_stack_depth
    ;       unpack_alignment
    ;       unpack_row_length
    ;       unpack_skip_pixels
    ;       unpack_skip_rows
    ;       vertex_array_size
    ;       vertex_array_stride.

:- type double_integer_state ---> max_viewport_dims.

:- pred get_integer(single_integer_state::in, int::out, io::di, io::uo)
    is det.

:- pred get_integer(double_integer_state::in, int::out, int::out,
    io::di, io::uo) is det.

:- type single_float_state
    --->    accum_clear_value
    ;       alpha_bias
    ;       alpha_scale
    ;       blue_bias
    ;       blue_scale
    ;       current_index
    ;       current_raster_distance
    ;       current_raster_index
    ;       depth_bias
    ;       depth_scale
    ;       fog_density
    ;       fog_end
    ;       fog_index
    ;       fog_start
    ;       green_bias
    ;       green_scale
    ;       index_clear_value
    ;       line_stipple_repeat
    ;       line_width
    ;       map1_grid_segments
    ;       point_size
    ;       polygon_offset_factor
    ;       polygon_offset_units
    ;       red_bias
    ;       red_scale
    ;       zoom_x
    ;       zoom_y.

:- type double_float_state
    --->    aliased_point_size_range
    ;       depth_range
    ;       map1_grid_domain
    ;       map2_grid_segments.

:- type triple_float_state ---> current_normal.

:- type quad_float_state
    --->    color_clear_value
    ;       current_color
    ;       current_raster_color
    ;       current_raster_position
    ;       current_texture_coords
    ;       fog_color
    ;       map2_grid_domain.

:- pred get_float(single_float_state::in, float::out, io::di, io::uo) is det.

:- pred get_float(double_float_state::in, float::out, float::out,
    io::di, io::uo) is det.

:- pred get_float(triple_float_state::in, float::out, float::out, float::out,
    io::di, io::uo) is det.

:- pred get_float(quad_float_state::in, float::out, float::out, float::out,
    float::out, io::di, io::uo) is det.

:- type string_name
    --->    vendor
    ;       renderer
    ;       version
    ;       extensions.

    % get_string(StrName, MaybeResult, !IO).
    % MaybeResult is yes(Result) where Result is a string containing
    % the requested information.  If the requested information is
    % not available then MaybeResult is no.
    % 
:- pred get_string(string_name::in, maybe(string)::out, io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Server attribute stack
%

:- type server_attrib_group
    --->    accum_buffer
    ;       color_buffer
    ;       current
    ;       depth_buffer
    ;       enable
    ;       eval
    ;       fog
    ;       hint
    ;       lighting
    ;       line
    ;       list
    ;       pixel_mode
    ;       point
    ;       polygon
    ;       polygon_stipple
    ;       scissor
    ;       stencil_buffer
    ;       transform
    ;       viewport.

    % Push *all* server attribute groups onto the stack.
    %
:- pred push_attrib(io::di, io::uo) is det.

:- pred push_attrib(list(server_attrib_group)::in, io::di, io::uo) is det.

:- pred pop_attrib(io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%
% Client attribute stack
%
    
    % There are others but these are the only two that can be pushed
    % onto the client attribute stack.
    %
:- type client_attrib_group
    --->    vertex_array
    ;       pixel_store.

:- pred push_client_attrib(io::di, io::uo) is det.

:- pred push_client_attrib(list(client_attrib_group)::in, io::di, io::uo)
    is det.

:- pred pop_client_attrib(io::di, io::uo) is det.

%------------------------------------------------------------------------------%
%------------------------------------------------------------------------------%

:- implementation.

:- import_module mogl.type_tables.

:- import_module exception.
:- import_module require.

%------------------------------------------------------------------------------%

    % XXX Check that this works on Windows.
    % We may need to #include <windows.h> to make it work.
:- pragma foreign_decl("C", "
    #include <stdio.h>
    #include <math.h>
    #include <assert.h>
    
    #if defined(__APPLE__) && defined(__MACH__)
        #include <OpenGL/gl.h>
    #else
        #include <GL/gl.h>
    #endif
").

:- pragma foreign_import_module("C", mogl.type_tables).

%------------------------------------------------------------------------------%
%
% GL errors
%

:- pragma foreign_enum("C", mogl.error/0, [
    no_error          - "GL_NO_ERROR",
    invalid_enum      - "GL_INVALID_ENUM",
    invalid_value     - "GL_INVALID_VALUE",
    invalid_operation - "GL_INVALID_OPERATION",
    stack_overflow    - "GL_STACK_OVERFLOW",
    stack_underflow   - "GL_STACK_UNDERFLOW",
    out_of_memory     - "GL_OUT_OF_MEMORY"
]).

:- pragma foreign_proc("C", 
    get_error(Err::out, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    Err = (MR_Integer) glGetError();
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Begin/end objects
%

:- pragma foreign_enum("C", block_mode/0, [
    points         - "GL_POINTS",
    line_strip     - "GL_LINE_STRIP",
    line_loop      - "GL_LINE_LOOP",
    lines          - "GL_LINES",
    polygon        - "GL_POLYGON",
    triangle_strip - "GL_TRIANGLE_STRIP",
    triangle_fan   - "GL_TRIANGLE_FAN",
    triangles      - "GL_TRIANGLES",
    quad_strip     - "GL_QUAD_STRIP",
    quads          - "GL_QUADS"
]).

:- pragma foreign_proc("C", 
    begin(Mode::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glBegin((GLenum) Mode);
    IO = IO0;
").

:- pragma foreign_proc("C", 
    end(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEnd();
    IO = IO0;
").

edge_flag(no, !IO) :-
    edge_flag_2(0, !IO).
edge_flag(yes, !IO) :-
    edge_flag_2(1, !IO).

:- pred edge_flag_2(int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    edge_flag_2(F::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEdgeFlag((GLboolean) F);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Vertex specification
%

:- pragma foreign_proc("C", 
    vertex2(X::in, Y::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glVertex2f((GLfloat) X, (GLfloat) Y);
    } else {
        glVertex2d((GLdouble) X, (GLdouble) Y);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    vertex3(X::in, Y::in, Z::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glVertex3f((GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glVertex3d((GLdouble) X, (GLdouble) Y, (GLdouble) Z);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    vertex4(X::in, Y::in, Z::in, W::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glVertex4f((GLfloat) X, (GLfloat) Y, (GLfloat) Z, (GLfloat) W);
    } else {
        glVertex4d((GLdouble) X, (GLdouble) Y, (GLdouble) Z,
            (GLdouble) W);
    }
    IO = IO0;
").

:- pragma foreign_proc("C",
    rect(X1::in, Y1::in, X2::in, Y2::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glRectf((GLfloat) X1, (GLfloat) Y1, (GLfloat) X2, (GLfloat) Y2);
    } else {
        glRectd((GLdouble) X1, (GLdouble) Y1, (GLdouble) X2, 
            (GLdouble) Y2);
    }
    IO = IO0;
").

%------------------------------------------------------------------------------%

:- pragma foreign_proc("C", 
    tex_coord1(X::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glTexCoord1f((GLfloat) X);
    } else {
        glTexCoord1d((GLdouble) X);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    tex_coord2(X::in, Y::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glTexCoord2f((GLfloat) X, (GLfloat) Y);
    } else {
        glTexCoord2d((GLdouble) X, (GLdouble) Y);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    tex_coord3(X::in, Y::in, Z::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glTexCoord3f((GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glTexCoord3d((GLdouble) X, (GLdouble) Y, (GLdouble) Z);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    tex_coord4(X::in, Y::in, Z::in, W::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glTexCoord4f((GLfloat) X, (GLfloat) Y, (GLfloat) Z,
            (GLfloat) W);
    } else {
        glTexCoord4d((GLdouble) X, (GLdouble) Y, (GLdouble) Z,
            (GLdouble) W);
    }
    IO = IO0;
").

%------------------------------------------------------------------------------%

:- pragma foreign_proc("C", 
    normal3(X::in, Y::in, Z::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glNormal3f((GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glNormal3d((GLdouble) X, (GLdouble) Y, (GLdouble) Z);
    }
    IO = IO0;
").

%------------------------------------------------------------------------------%

:- pragma foreign_proc("C", 
    color3(R::in, G::in, B::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glColor3f((GLfloat) R, (GLfloat) G, (GLfloat) B);
    } else {
        glColor3d((GLdouble) R, (GLdouble) G, (GLdouble) B);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    color4(R::in, G::in, B::in, A::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glColor4f((GLfloat) R, (GLfloat) G, (GLfloat) B, (GLfloat) A);
    } else {
        glColor4d((GLdouble) R, (GLdouble) G, (GLdouble) B,
            (GLdouble) A);
    }
    IO = IO0;
").

:- pragma foreign_proc("C",
    index(I::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glIndexf((GLfloat) I);
    } else {
        glIndexd((GLdouble) I);
    }
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Coordinate transformations
%

:- pragma foreign_proc("C", 
    depth_range(Near::in, Far::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glDepthRange((GLclampd) Near, (GLclampd) Far);
    IO = IO0;
").

:- pragma foreign_proc("C", 
    viewport(X::in, Y::in, Wdth::in, Hght::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glViewport((GLint) X, (GLint) Y, (GLsizei) Wdth, (GLsizei) Hght);
    IO = IO0;
").

%------------------------------------------------------------------------------%

:- pragma foreign_enum("C", matrix_mode/0, [
    texture    - "GL_TEXTURE",
    modelview  - "GL_MODELVIEW",
    projection - "GL_PROJECTION"
]).

:- pragma foreign_proc("C", 
    matrix_mode(MatrixMode::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glMatrixMode((GLenum) MatrixMode);
    IO = IO0;
").

:- pragma foreign_proc("C",
    get_matrix_mode(MatrixMode::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLint v;

    glGetIntegerv(GL_MATRIX_MODE, &v);
    MatrixMode = (MR_Integer) v;
    IO = IO0;
").

load_matrix(Matrix, !IO) :-
    Matrix = m(
        A1, A5, A9,  A13,
        A2, A6, A10, A14,
        A3, A7, A11, A15,
        A4, A8, A12, A16
    ),
    load_matrix_2(A1, A2, A3, A4, A5, A6, A7, A8,
        A9, A10, A11, A12, A13, A14, A15, A16, !IO).

:- pred load_matrix_2(
    float::in, float::in, float::in, float::in,
    float::in, float::in, float::in, float::in,
    float::in, float::in, float::in, float::in,
    float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    load_matrix_2(A1::in, A2::in, A3::in, A4::in,
        A5::in, A6::in, A7::in, A8::in,
        A9::in, A10::in, A11::in, A12::in,
        A13::in, A14::in, A15::in, A16::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        GLfloat a[16];

        a[0] = (GLfloat) A1; a[1] = (GLfloat) A2;
        a[2] = (GLfloat) A3; a[3] = (GLfloat) A4;
        a[4] = (GLfloat) A5; a[5] = (GLfloat) A6;
        a[6] = (GLfloat) A7; a[7] = (GLfloat) A8;
        a[8] = (GLfloat) A9; a[9] = (GLfloat) A10;
        a[10] = (GLfloat) A11; a[11] = (GLfloat) A12;
        a[12] = (GLfloat) A13; a[13] = (GLfloat) A14;
        a[14] = (GLfloat) A15; a[15] = (GLfloat) A16;
        glLoadMatrixf(a);
    } else {
        GLdouble a[16];

        a[0] = (GLdouble) A1; a[1] = (GLdouble) A2;
        a[2] = (GLdouble) A3; a[3] = (GLdouble) A4;
        a[4] = (GLdouble) A5; a[5] = (GLdouble) A6;
        a[6] = (GLdouble) A7; a[7] = (GLdouble) A8;
        a[8] = (GLdouble) A9; a[9] = (GLdouble) A10;
        a[10] = (GLdouble) A11; a[11] = (GLdouble) A12;
        a[12] = (GLdouble) A13; a[13] = (GLdouble) A14;
        a[14] = (GLdouble) A15; a[15] = (GLdouble) A16;
        glLoadMatrixd(a);
    }
    IO = IO0;
").

mult_matrix(Matrix, !IO) :-
    Matrix = m(
        A1, A5, A9, A13,
        A2, A6, A10, A14,
        A3, A7, A11, A15,
        A4, A8, A12, A16
    ),
    mult_matrix2(A1, A2, A3, A4, A5, A6, A7, A8,
        A9, A10, A11, A12, A13, A14, A15, A16, !IO).

:- pred mult_matrix2(
        float::in, float::in, float::in, float::in,
        float::in, float::in, float::in, float::in,
        float::in, float::in, float::in, float::in,
        float::in, float::in, float::in, float::in,
        io::di, io::uo) is det.
:- pragma foreign_proc("C",
    mult_matrix2(A1::in, A2::in, A3::in, A4::in,
        A5::in, A6::in, A7::in, A8::in,
        A9::in, A10::in, A11::in, A12::in,
        A13::in, A14::in, A15::in, A16::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        GLfloat a[16];

        a[0] = (GLfloat) A1; a[1] = (GLfloat) A2;
        a[2] = (GLfloat) A3; a[3] = (GLfloat) A4;
        a[4] = (GLfloat) A5; a[5] = (GLfloat) A6;
        a[6] = (GLfloat) A7; a[7] = (GLfloat) A8;
        a[8] = (GLfloat) A9; a[9] = (GLfloat) A10;
        a[10] = (GLfloat) A11; a[11] = (GLfloat) A12;
        a[12] = (GLfloat) A13; a[13] = (GLfloat) A14;
        a[14] = (GLfloat) A15; a[15] = (GLfloat) A16;
        glMultMatrixf(a);
    } else {
        GLdouble a[16];
        
        a[0] = (GLdouble) A1; a[1] = (GLdouble) A2;
        a[2] = (GLdouble) A3; a[3] = (GLdouble) A4;
        a[4] = (GLdouble) A5; a[5] = (GLdouble) A6;
        a[6] = (GLdouble) A7; a[7] = (GLdouble) A8;
        a[8] = (GLdouble) A9; a[9] = (GLdouble) A10;
        a[10] = (GLdouble) A11; a[11] = (GLdouble) A12;
        a[12] = (GLdouble) A13; a[13] = (GLdouble) A14;
        a[14] = (GLdouble) A15; a[15] = (GLdouble) A16;
        glMultMatrixd(a);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    load_identity(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLoadIdentity();
    IO = IO0;
").

:- pragma foreign_proc("C", 
    rotate(Theta::in, X::in, Y::in, Z::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glRotatef((GLfloat) Theta,
            (GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glRotated((GLdouble) Theta,
            (GLdouble) X, (GLdouble) Y, (GLdouble) Z);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    translate(X::in, Y::in, Z::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glTranslatef((GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glTranslated((GLdouble) X, (GLdouble) Y, (GLdouble) Z);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    scale(X::in, Y::in, Z::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glScalef((GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glScaled((GLdouble) X, (GLdouble) Y, (GLdouble) Z);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    frustum(L::in, R::in, B::in, T::in, N::in, F::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFrustum((GLdouble) L, (GLdouble) R, (GLdouble) B,
        (GLdouble) T, (GLdouble) N, (GLdouble) F);
    IO = IO0;
").

:- pragma foreign_proc("C", 
    ortho(L::in, R::in, B::in, T::in, N::in, F::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glOrtho((GLdouble) L, (GLdouble) R, (GLdouble) B,
        (GLdouble) T, (GLdouble) N, (GLdouble) F);
    IO = IO0;
").

:- pragma foreign_proc("C", 
    push_matrix(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPushMatrix();
    IO = IO0;
").

:- pragma foreign_proc("C", 
    pop_matrix(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPopMatrix();
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Clipping
%

clip_plane(Num, clip(X, Y, Z, W), !IO) :-
    clip_plane_2(Num, X, Y, Z, W, !IO).

:- pred clip_plane_2(int::in, float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    clip_plane_2(I::in, X::in, Y::in, Z::in, W::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLdouble p[4];

    p[0] = (GLdouble) X;
    p[1] = (GLdouble) Y;
    p[2] = (GLdouble) Z;
    p[3] = (GLdouble) W;
    glClipPlane(GL_CLIP_PLANE0+I, p);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Current raster position
%

:- pragma foreign_proc("C", 
    raster_pos2(X::in, Y::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
" 
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glRasterPos2f((GLfloat) X, (GLfloat) Y);
    } else {
        glRasterPos2d((GLdouble) X, (GLdouble) Y);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    raster_pos3(X::in, Y::in, Z::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
" 
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glRasterPos3f((GLfloat) X, (GLfloat) Y, (GLfloat) Z);
    } else {
        glRasterPos3d((GLdouble) X, (GLdouble) Y, (GLfloat) Z);
    }
    IO = IO0;
").

:- pragma foreign_proc("C", 
    raster_pos4(X::in, Y::in, Z::in, W::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
" 
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glRasterPos4f((GLfloat) X, (GLfloat) Y, (GLfloat) Z,
            (GLfloat) W);
    } else {
        glRasterPos4d((GLdouble) X, (GLdouble) Y, (GLfloat) Z,
            (GLdouble) W);
    }
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Colors and coloring
%

:- pragma foreign_enum("C", face_direction/0, [
    cw  - "GL_CW",
    ccw - "GL_CCW"
]).

:- pragma foreign_enum("C", face_side/0, [
    front - "GL_FRONT",
    back  - "GL_BACK",
    front_and_back - "GL_FRONT_AND_BACK"
]).

:- pragma foreign_enum("C", color_material_mode/0, [
    ambient - "GL_AMBIENT",
    diffuse - "GL_DIFFUSE",
    ambient_and_diffuse - "GL_AMBIENT_AND_DIFFUSE",
    specular - "GL_SPECULAR",
    emission - "GL_EMISSION"
]).

:- pragma foreign_enum("C", shade_model/0, [
    smooth - "GL_SMOOTH",
    flat   - "GL_FLAT"
]).

:- pragma foreign_proc("C", 
    front_face(F::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFrontFace((GLenum) F);
    IO = IO0;
").

material(Face, ambient(R, G, B, A), !IO) :-
    material_ambient(Face, R, G, B, A, !IO).
material(Face, diffuse(R, G, B, A), !IO)  :-
    material_diffuse(Face, R, G, B, A, !IO).
material(Face, ambient_and_diffuse(R, G, B, A), !IO) :- 
    material_ambient_and_diffuse(Face, R, G, B, A, !IO).
material(Face, specular(R, G, B, A), !IO) :-
    material_specular(Face, R, G, B, A, !IO).
material(Face, emission(R, G, B, A), !IO) :-
    material_emission(Face, R, G, B, A, !IO).
material(Face, shininess(S), !IO) :-
    material_shininess(Face, S, !IO).
material(Face, color_indexes(R, G, B), !IO) :-
    material_color_indexes(Face, R, G, B, !IO).

:- pred material_ambient(face_side::in, float::in, float::in, float::in,
    float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_ambient(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glMaterialfv((GLenum) F, GL_AMBIENT, params);
    IO = IO0;
").

:- pred material_diffuse(face_side::in, float::in, float::in, float::in,
    float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_diffuse(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glMaterialfv((GLenum) F, GL_DIFFUSE, params);
    IO = IO0;
").

:- pred material_ambient_and_diffuse(face_side::in, float::in, float::in,
    float::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_ambient_and_diffuse(F::in, R::in, G::in, B::in, A::in, IO0::di,
        IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glMaterialfv((GLenum) F, GL_AMBIENT_AND_DIFFUSE, params);
    IO = IO0;
").

:- pred material_specular(face_side::in, float::in, float::in, float::in,
    float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_specular(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glMaterialfv((GLenum) F, GL_SPECULAR, params);
    IO = IO0;
").

:- pred material_emission(face_side::in, float::in, float::in, float::in,
    float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_emission(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glMaterialfv((GLenum) F, GL_EMISSION, params);
    IO = IO0;
").

:- pred material_shininess(face_side::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_shininess(F::in, S::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glMaterialf((GLenum) F, GL_SHININESS, (GLfloat) S);
    IO = IO0;
").

:- pred material_color_indexes(face_side::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    material_color_indexes(F::in, R::in, G::in, B::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[3];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    glMaterialfv((GLenum) F, GL_COLOR_INDEXES, params);
    IO = IO0;
").

light(Num, ambient(R, G, B, A), !IO) :-
    light_ambient(Num, R, G, B, A, !IO).
light(Num, diffuse(R, G, B, A), !IO) :-
    light_diffuse(Num, R, G, B, A, !IO).
light(Num, specular(R, G, B, A), !IO) :-
    light_specular(Num, R, G, B, A, !IO).
light(Num, position(X, Y, Z, W), !IO) :- 
    light_position(Num, X, Y, Z, W, !IO).
light(Num, spot_direction(I, J, K), !IO) :-
    light_spot_direction(Num, I, J, K, !IO).
light(Num, spot_exponent(K), !IO) :-
    light_spot_exponent(Num, K, !IO).
light(Num, spot_cutoff(K), !IO)  :-
    light_spot_cutoff(Num, K, !IO).
light(Num, constant_attenuation(K), !IO) :-
    light_constant_attenuation(Num, K, !IO).
light(Num, linear_attenuation(K), !IO) :-
    light_linear_attenuation(Num, K, !IO).
light(Num, quadratic_attenuation(K), !IO) :-
    light_quadratic_attenuation(Num, K, !IO).

:- pred light_ambient(int::in, float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_ambient(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glLightfv(F + GL_LIGHT0, GL_AMBIENT, params);
    IO = IO0;
").

:- pred light_diffuse(int::in, float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_diffuse(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glLightfv(F + GL_LIGHT0, GL_DIFFUSE, params);
    IO = IO0;
").

:- pred light_specular(int::in, float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_specular(F::in, R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glLightfv(F + GL_LIGHT0, GL_SPECULAR, params);
    IO = IO0;
").

:- pred light_position(int::in, float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_position(F::in, X::in, Y::in, Z::in, W::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) X;
    params[1] = (GLfloat) Y;
    params[2] = (GLfloat) Z;
    params[3] = (GLfloat) W;
    glLightfv(F + GL_LIGHT0, GL_POSITION, params);
    IO = IO0;
").

:- pred light_spot_direction(int::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_spot_direction(F::in, I::in, J::in, K::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[3];

    params[0] = (GLfloat) I;
    params[1] = (GLfloat) J;
    params[2] = (GLfloat) K;
    glLightfv(F + GL_LIGHT0, GL_SPOT_DIRECTION, params);
    IO = IO0;
").

:- pred light_spot_exponent(int::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_spot_exponent(F::in, E::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightf(F + GL_LIGHT0, GL_SPOT_EXPONENT, (GLfloat) E);
    IO = IO0;
").

:- pred light_spot_cutoff(int::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    light_spot_cutoff(F::in, E::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightf(F + GL_LIGHT0, GL_SPOT_CUTOFF, (GLfloat) E);
    IO = IO0;
").

:- pred light_constant_attenuation(int::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    light_constant_attenuation(F::in, E::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightf(F + GL_LIGHT0, GL_CONSTANT_ATTENUATION, (GLfloat) E);
    IO = IO0;
").

:- pred light_linear_attenuation(int::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    light_linear_attenuation(F::in, E::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightf(F + GL_LIGHT0, GL_LINEAR_ATTENUATION, (GLfloat) E);
    IO = IO0;
").

:- pred light_quadratic_attenuation(int::in, float::in, io::di, io::uo)
    is det.
:- pragma foreign_proc("C",
    light_quadratic_attenuation(F::in, E::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightf(F + GL_LIGHT0, GL_QUADRATIC_ATTENUATION, (GLfloat) E);
    IO = IO0;
").

:- func bool_to_int(bool) = int.

bool_to_int(no) = 0.
bool_to_int(yes) = 1.

light_model(light_model_ambient(R, G, B, A), !IO) :-
    light_model_ambient(R, G, B, A, !IO).
light_model(light_model_local_viewer(Bool), !IO) :-
    light_model_local_viewer(bool_to_int(Bool), !IO).
light_model(light_model_two_side(Bool), !IO) :-
    light_model_two_side(bool_to_int(Bool), !IO).

:- pred light_model_ambient(float::in, float::in, float::in, float::in, io::di,
    io::uo) is det.
:- pragma foreign_proc("C",
    light_model_ambient(R::in, G::in, B::in, A::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat params[4];

    params[0] = (GLfloat) R;
    params[1] = (GLfloat) G;
    params[2] = (GLfloat) B;
    params[3] = (GLfloat) A;
    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, params);
    IO = IO0;
").

:- pred light_model_local_viewer(int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    light_model_local_viewer(F::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightModeli(GL_LIGHT_MODEL_LOCAL_VIEWER, (GLint) F);
    IO = IO0;
").

:- pred light_model_two_side(int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    light_model_two_side(F::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, (GLint) F);
    IO = IO0;
").

:- pragma foreign_proc("C",
    color_material(Face::in, Mode::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glColorMaterial((GLenum) Face, (GLenum) Mode);
    IO = IO0;
").

:- pragma foreign_proc("C",
    shade_model(Model::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glShadeModel((GLenum) Model);
    IO = IO0;
").

:- pragma foreign_proc("C",
    get_shade_model(Value::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLint v;
    
    glGetIntegerv(GL_SHADE_MODEL, &v);
    Value = (MR_Integer) v;
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Points
%

:- pragma foreign_proc("C",
    point_size(Size::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPointSize((GLfloat) Size);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Line segments
%

:- pragma foreign_proc("C",
    line_width(Size::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLineWidth((GLfloat) Size);
    IO = IO0;
").

:- pragma foreign_proc("C",
    line_stipple(Fac::in, Pat::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLineStipple((GLint) Fac, (GLushort) Pat);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Polygons
%

:- pragma foreign_enum("C", polygon_mode/0, [
    point - "GL_POINT",
    line  - "GL_LINE",
    fill  - "GL_FILL"
]).

:- pragma foreign_proc("C",
    cull_face(F::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glCullFace((GLenum) F);
    IO = IO0;
").

:- pragma foreign_proc("C",
    polygon_stipple(Mask::bitmap_ui, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPolygonStipple((GLubyte *) Mask->elements);
    IO = IO0;
").

:- pragma foreign_proc("C",
    polygon_mode(Face::in, Mode::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPolygonMode((GLenum) Face, (GLenum) Mode);
    IO = IO0;
").

:- pragma foreign_proc("C",
    polygon_offset(Fac::in, Units::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPolygonOffset((GLfloat) Fac, (GLfloat) Units);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Pixel rectangles
%

:- pragma foreign_decl("C", "
    extern const GLenum pixel_store_parameter_flags[];
").

:- pragma foreign_code("C", "
    const GLenum pixel_store_parameter_flags[] = {
        GL_PACK_SWAP_BYTES,
        GL_PACK_LSB_FIRST,
        GL_PACK_ROW_LENGTH,
        GL_PACK_IMAGE_HEIGHT,
        GL_PACK_SKIP_ROWS,
        GL_PACK_SKIP_PIXELS,
        GL_PACK_SKIP_IMAGES,
        GL_PACK_ALIGNMENT,
        GL_UNPACK_SWAP_BYTES,
        GL_UNPACK_LSB_FIRST,
        GL_UNPACK_ROW_LENGTH,
        GL_UNPACK_IMAGE_HEIGHT,
        GL_UNPACK_SKIP_ROWS,
        GL_UNPACK_SKIP_PIXELS,
        GL_UNPACK_SKIP_IMAGES,
        GL_UNPACK_ALIGNMENT
    };
").

:- pred pixel_store_parameter_to_ints(pixel_store_parameter::in, int::out,
    int::out) is det.

pixel_store_parameter_to_ints(pack_swap_bytes(Param), 0, bool_to_int(Param)).
pixel_store_parameter_to_ints(pack_lsb_first(Param), 1, bool_to_int(Param)).
pixel_store_parameter_to_ints(pack_row_length(Param), 2, Param).
pixel_store_parameter_to_ints(pack_image_height(Param), 3, Param).
pixel_store_parameter_to_ints(pack_skip_rows(Param), 4, Param).
pixel_store_parameter_to_ints(pack_skip_pixels(Param), 5, Param).
pixel_store_parameter_to_ints(pack_skip_images(Param), 6, Param).
pixel_store_parameter_to_ints(pack_alignment(Param), 7, Param).
pixel_store_parameter_to_ints(unpack_swap_bytes(Param), 8, bool_to_int(Param)).
pixel_store_parameter_to_ints(unpack_lsb_first(Param), 9, bool_to_int(Param)).
pixel_store_parameter_to_ints(unpack_row_length(Param), 10, Param).
pixel_store_parameter_to_ints(unpack_image_height(Param), 11, Param).
pixel_store_parameter_to_ints(unpack_skip_rows(Param), 12, Param).
pixel_store_parameter_to_ints(unpack_skip_pixels(Param), 13, Param).
pixel_store_parameter_to_ints(unpack_skip_images(Param), 14, Param).
pixel_store_parameter_to_ints(unpack_alignment(Param), 15, Param).

pixel_store(Param, !IO) :-
    pixel_store_parameter_to_ints(Param, PName, Value),
    pixel_store_2(PName, Value, !IO).

:- pred pixel_store_2(int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    pixel_store_2(PName::in, Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPixelStorei(pixel_store_parameter_flags[PName], (GLint) Param);
    IO = IO0;
").

:- pragma foreign_proc("C",
    pixel_zoom(X::in, Y::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io,  promise_pure,
        does_not_affect_liveness],
"
    glPixelZoom((GLfloat) X, (GLfloat) Y);
    IO = IO0;
").

:- pragma foreign_decl("C", "
    extern const GLenum pixel_transfer_mode_flags[];
").

:- pragma foreign_code("C", "
    const GLenum pixel_transfer_mode_flags[] = {
        GL_MAP_COLOR,
        GL_MAP_STENCIL,
        GL_INDEX_SHIFT,
        GL_INDEX_OFFSET,
        GL_RED_SCALE,
        GL_GREEN_SCALE,
        GL_BLUE_SCALE,
        GL_ALPHA_SCALE,
        GL_RED_BIAS,
        GL_GREEN_BIAS,
        GL_BLUE_BIAS,
        GL_ALPHA_BIAS,
        GL_DEPTH_BIAS
    };
").
    
    % The magic numbers below are indicies into the
    % `pixel_transfer_mode_flags' array.
pixel_transfer(map_color(Bool), !IO) :-
    pixel_transferi(0, bool_to_int(Bool), !IO).
pixel_transfer(map_stencil(Bool), !IO) :-
    pixel_transferi(1, bool_to_int(Bool), !IO).
pixel_transfer(index_shift(Shift), !IO) :-
    pixel_transferi(2, Shift, !IO).
pixel_transfer(index_offset(Offset), !IO) :-
    pixel_transferi(3, Offset, !IO). 
pixel_transfer(red_scale(Factor), !IO) :-
    pixel_transferf(4, Factor, !IO).
pixel_transfer(green_scale(Factor), !IO) :-
    pixel_transferf(5, Factor, !IO).
pixel_transfer(blue_scale(Factor), !IO) :-
    pixel_transferf(6, Factor, !IO).
pixel_transfer(alpha_scale(Factor), !IO) :-
    pixel_transferf(7, Factor, !IO).
pixel_transfer(red_bias(Bias), !IO) :-
    pixel_transferf(8, Bias, !IO).
pixel_transfer(green_bias(Bias), !IO) :-
    pixel_transferf(9, Bias, !IO).
pixel_transfer(blue_bias(Bias), !IO) :-
    pixel_transferf(10, Bias, !IO).
pixel_transfer(alpha_bias(Bias), !IO) :-
    pixel_transferf(11, Bias, !IO).
pixel_transfer(depth_bias(Bias), !IO) :-
    pixel_transferf(12, Bias, !IO).

:- pred pixel_transferi(int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    pixel_transferi(Pname::in, Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPixelTransferi(pixel_transfer_mode_flags[Pname], Param);
    IO = IO0;
").

:- pred pixel_transferf(int::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    pixel_transferf(Pname::in, Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPixelTransferf(pixel_transfer_mode_flags[Pname], (GLfloat) Param);
    IO = IO0;
").

:- pragma foreign_enum("C", copy_type/0, [
    color   - "GL_COLOR",
    stencil - "GL_STENCIL",
    depth   - "GL_DEPTH"
]).

:- pragma foreign_proc("C",
    copy_pixels(X::in, Y::in, W::in, H::in, WhatFlag::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glCopyPixels((GLint) X, (GLint) Y, (GLsizei) W, (GLsizei) H,
        (GLenum) WhatFlag);
    IO = IO0;
").

:- type pixels
    --->    pixels(
                pixel_format :: int,
                pixel_type   :: int,
                pixel_data   :: pixel_data
            ).

read_buffer(Buffer, !IO) :-
    read_buffer_to_int_and_offset(Buffer, BufferFlag, Offset),
    read_buffer_2(BufferFlag, Offset, !IO).

:- pred read_buffer_2(int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    read_buffer_2(BufferFlag::in, Offset::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glReadBuffer(buffer_flags[BufferFlag] + Offset);
    IO = IO0;
").
    % The draw and read buffer types both map
    % into the same array - hence the indices here
    % start at 1 rather than 0 (corresponding to
    % none, which is only for draw buffers).
    %
:- pred read_buffer_to_int_and_offset(read_buffer::in, int::out, int::out)
    is det.

read_buffer_to_int_and_offset(front_left, 1, 0).
read_buffer_to_int_and_offset(front_right, 2, 0).
read_buffer_to_int_and_offset(back_left, 3, 0).
read_buffer_to_int_and_offset(back_right, 4, 0).
read_buffer_to_int_and_offset(front, 5, 0).
read_buffer_to_int_and_offset(back, 6, 0).
read_buffer_to_int_and_offset(left, 7, 0).
read_buffer_to_int_and_offset(right, 8, 0).
read_buffer_to_int_and_offset(front_and_back, 9, 0).
read_buffer_to_int_and_offset(aux(I), 10, I).

%------------------------------------------------------------------------------%
%
% Bitmaps
%

mogl.bitmap(Width, Height, XOrig, YOrig, XMove, YMove, Bitmap, !IO) :-
    ( num_bits(Bitmap) < Width * Height ->
        throw(software_error("mogl.bitmap/9: bitmap is to small."))
    ;
        bitmap_2(Width, Height, XOrig, YOrig, XMove, YMove, Bitmap, !IO)
    ).

:- pred bitmap_2(int::in, int::in, float::in, float::in, float::in, float::in,
    bitmap::bitmap_ui, io::di, io::uo) is det.

:- pragma foreign_proc("C",
    bitmap_2(Width::in, Height::in, XOrig::in, YOrig::in,
        XMove::in, YMove::in, Bitmap::bitmap_ui, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"

    glBitmap((GLsizei) Width, (GLsizei) Height, (GLfloat) XOrig,
        (GLfloat) YOrig, (GLfloat) XMove, (GLfloat) YMove,
        (GLubyte *)  Bitmap->elements);
    IO = IO0; 
").

%------------------------------------------------------------------------------%
%
% Texture mapping
%

:- pragma foreign_enum("C", texture_target/0, [
    texture_1d       - "GL_TEXTURE_1D",
    proxy_texture_1d - "GL_PROXY_TEXTURE_1D",
    texture_2d       - "GL_TEXTURE_2D",
    proxy_texture_2d - "GL_PROXY_TEXTURE_2D"
]).

:- pragma foreign_decl("C", "
    extern const GLenum texture_format_flags[];
").

:- pragma foreign_decl("C", "
    extern const GLenum texture_parameter_flags[];
").

    % NOTE: if you alter this array make sure that you change 
    % mogl.tex_parameter/5 accordingly.
:- pragma foreign_code("C", "
    const GLenum texture_parameter_flags[] = {
        GL_TEXTURE_WRAP_S,
        GL_TEXTURE_WRAP_T,
        GL_TEXTURE_MIN_FILTER,
        GL_TEXTURE_MAG_FILTER
        /*
        ** NOTE: these two cases are handled separately at
        ** the moment so we don't use them here.
        **
        ** GL_TEXTURE_BORDER_COLOR,
        ** GL_TEXTURE_PRIORITY
        */
    };
").

:- pragma foreign_enum("C", wrap_mode/0, [
    clamp  - "GL_CLAMP",
    repeat - "GL_REPEAT"
]).

:- pragma foreign_enum("C", min_filter_method/0, [
    nearest - "GL_NEAREST",
    linear  - "GL_LINEAR",
    nearest_mipmap_nearest - "GL_NEAREST_MIPMAP_NEAREST",
    nearest_mipmap_linear  - "GL_NEAREST_MIPMAP_LINEAR",
    linear_mipmap_nearest  - "GL_LINEAR_MIPMAP_NEAREST",
    linear_mipmap_linear   - "GL_LINEAR_MIPMAP_LINEAR"
]).

:- pragma foreign_enum("C", mag_filter_method/0, [
    nearest - "GL_NEAREST",
    linear  - "GL_LINEAR"
]).

    % NOTE: the magic numbers below are indicies into the
    % texture_parameter_flags array.
    %
tex_parameter(Target, wrap_s(WrapMode), !IO) :- 
    tex_parameter_wrap(Target, 0, WrapMode, !IO).
tex_parameter(Target, wrap_t(WrapMode), !IO) :-
    tex_parameter_wrap(Target, 1, WrapMode, !IO).
tex_parameter(Target, min_filter(FilterMethod), !IO) :-
    tex_parameter_min_filter(Target, 2, FilterMethod, !IO).
tex_parameter(Target, mag_filter(FilterMethod), !IO) :-
    tex_parameter_mag_filter(Target, 2, FilterMethod, !IO).
tex_parameter(Target, border_color(R, G, B, A), !IO) :-
    tex_parameter_border_color(Target, R, G, B, A, !IO).
tex_parameter(Target, priority(Priority), !IO) :-
    tex_parameter_priority(Target, Priority, !IO).

:- pred tex_parameter_wrap(texture_target::in, int::in, wrap_mode::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_parameter_wrap(Target::in, Pname::in, Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexParameteri((GLenum) Target, texture_parameter_flags[Pname],
        (GLenum) Param);
    IO = IO0;
").

:- pred tex_parameter_min_filter(texture_target::in, int::in,
    min_filter_method::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    tex_parameter_min_filter(Target::in, Pname::in, Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexParameteri((GLenum) Target, texture_parameter_flags[Pname],
        (GLenum) Param);
    IO = IO0;
").

:- pred tex_parameter_mag_filter(texture_target::in, int::in,
    mag_filter_method::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    tex_parameter_mag_filter(Target::in, Pname::in, Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexParameteri((GLenum) Target, texture_parameter_flags[Pname],
        (GLenum) Param);
    IO = IO0;
").

:- pred tex_parameter_border_color(texture_target::in,
    float::in, float::in, float::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    tex_parameter_border_color(Target::in, Red::in, Blue::in, Green::in,
        Alpha::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat border_color[4] = {
        (GLfloat) Red,
        (GLfloat) Blue,
        (GLfloat) Green,
        (GLfloat) Alpha
    };

    glTexParameterfv((GLenum) Target, GL_TEXTURE_BORDER_COLOR, border_color);
    IO = IO0;
").

:- pred tex_parameter_priority(texture_target::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C",
    tex_parameter_priority(Target::in, Priority::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexParameterf((GLenum) Target, GL_TEXTURE_PRIORITY, (GLfloat) Priority);
    IO = IO0;
").

:- pragma foreign_proc("C", 
    bind_texture(Target::in(non_proxy_texture_target), TexName::in,
        IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glBindTexture((GLenum) Target, (GLuint) TexName);
    IO = IO0;
").

delete_textures([], !IO).
delete_textures(Textures @ [_ | _], !IO) :-
    list.length(Textures, NumTextures),
    delete_textures_2(Textures, NumTextures, !IO).

:- pred delete_textures_2(list(texture_name)::in, int::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    delete_textures_2(Textures::in, NumTextures::in, IO0::di, IO::uo),
    [may_call_mercury, promise_pure, tabled_for_io, terminates,
        will_not_throw_exception],
"
    GLuint *textures;
    int i = 0;

    textures = MR_GC_NEW_ARRAY(GLuint, NumTextures);

    while (!MR_list_is_empty(Textures)) {
        textures[i++] = MR_list_head(Textures);
        Textures = MR_list_tail(Textures);
    }

    glDeleteTextures((GLsizei) NumTextures, textures);
    assert(glGetError() == GL_NO_ERROR);
    
    MR_GC_free(textures);

    IO = IO0;
").    

:- pragma foreign_proc("C",
    gen_textures(Num::in, Textures::out, IO0::di, IO::uo),
    [may_call_mercury, promise_pure, tabled_for_io, terminates,
        will_not_throw_exception],
"
    GLuint *new_textures;
    int i;

    new_textures = MR_GC_NEW_ARRAY(GLuint, Num);
    
    glGenTextures((GLsizei) Num, new_textures);
    assert(glGetError() == GL_NO_ERROR);

    Textures = MR_list_empty();
    
    for (i = 0; i < Num; i++) {
        Textures = MR_list_cons(new_textures[i], Textures);
    }

    MR_GC_free(new_textures);
    
    IO = IO0;
").
    
:- pragma foreign_proc("C",
    is_texture(Name::in, IsTexture::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    if (glIsTexture(Name)) {
        IsTexture = MR_YES;
    } else {
        IsTexture = MR_NO;
    }
    IO = IO0;
").

:- pragma foreign_enum("C", texture_function/0, [
    decal    - "GL_DECAL",
    replace  - "GL_REPLACE",
    modulate - "GL_MODULATE",
    blend    - "GL_BLEND"
]).

tex_env(_, texture_env_mode(Function), !IO) :-
    tex_env_mode(Function, !IO).
tex_env(_, texture_env_color(R, G, B, A), !IO) :-
    tex_env_color(R, G, B, A, !IO).

:- pred tex_env_mode(texture_function::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_env_mode(Param::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure, 
        does_not_affect_liveness], 
"
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, (GLenum) Param);
    IO = IO0;
").

:- pred tex_env_color(float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C",
    tex_env_color(Red::in, Green::in, Blue::in, Alpha::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    GLfloat env_color[] = {
        (GLfloat) Red, 
        (GLfloat) Green, 
        (GLfloat) Blue, 
        (GLfloat) Alpha 
    };

    glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, env_color);
    IO = IO0;
").

:- pragma foreign_enum("C", texture_coord/0, [
    s - "GL_S",
    t - "GL_T",
    r - "GL_R",
    q - "GL_Q"
]).


:- pragma foreign_enum("C", texture_gen_function/0, [
    object_linear - "GL_OBJECT_LINEAR",
    eye_linear    - "GL_EYE_LINEAR",
    sphere_map    - "GL_SPHERE_MAP"
]).

tex_gen(Coord, texture_gen_mode(TexGenFunc), !IO) :-
    tex_geni(Coord, TexGenFunc, !IO).
tex_gen(Coord, object_plane(X, Y, Z, W), !IO) :-
    tex_genf_object_plane(Coord, X, Y, Z, W, !IO).
tex_gen(Coord, eye_plane(X, Y, Z, W), !IO) :-
    tex_genf_eye_plane(Coord, X, Y, Z, W, !IO).

:- pred tex_geni(texture_coord::in, texture_gen_function::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_geni(Coord::in, TexGenFunc::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexGeni((GLenum) Coord, GL_TEXTURE_GEN_MODE, (GLenum) TexGenFunc);
    IO = IO0;
").

:- pred tex_genf_object_plane(texture_coord::in, float::in, float::in,
    float::in, float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_genf_object_plane(Coord::in, X::in, Y::in, Z::in, W::in, IO0::di,
        IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        GLfloat coefficients[] = {
            (GLfloat) X,
            (GLfloat) Y,
            (GLfloat) Z,
            (GLfloat) W
        };

        glTexGenfv((GLenum) Coord, GL_OBJECT_PLANE, coefficients);
    } else {
        GLdouble coefficients[] = {
            (GLdouble) X,
            (GLdouble) Y,
            (GLdouble) Z,
            (GLdouble) W
        };

        glTexGendv((GLenum) Coord, GL_OBJECT_PLANE, coefficients);
    }
    IO = IO0;
").

:- pred tex_genf_eye_plane(texture_coord::in, float::in, float::in, float::in,
    float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_genf_eye_plane(Coord::in, X::in, Y::in, Z::in, W::in, IO0::di,
        IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
" 
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        GLfloat coefficients[] = {
            (GLfloat) X,
            (GLfloat) Y,
            (GLfloat) Z,
            (GLfloat) W
        };
        
        glTexGenfv((GLenum) Coord, GL_EYE_PLANE, coefficients);
    } else {
        GLdouble coefficients[] = {
            (GLdouble) X,
            (GLdouble) Y,
            (GLdouble) Z,
            (GLdouble) W
        };

        glTexGendv((GLenum) Coord, GL_EYE_PLANE, coefficients);
    }
    IO = IO0;
").

tex_image_1d(Target, Level, InternalFormat, Width, Border,
        Format, Type, Pixels, !IO) :-
    texture_format_to_int(InternalFormat, InternalFormatInt),
    tex_image_1d_2(Target, Level, InternalFormatInt, Width, Border,
        pixel_format_to_int(Format), pixel_type_to_int(Type), Pixels, !IO).

:- pred tex_image_1d_2(texture_target::in, int::in, int::in, int::in, int::in,
    int::in, int::in, pixel_data::bitmap_ui, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_image_1d_2(Target::in, Level::in, InternalFormat::in,
        Width::in, Border::in, Format::in, Type::in,
        Pixels::bitmap_ui, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexImage1D((GLenum) Target, Level,
        texture_format_flags[InternalFormat], Width, Border,
        pixel_format_flags[Format], pixel_type_flags[Type], Pixels->elements);
    IO = IO0;
").

tex_image_2d(Target, Level, InternalFormat, Width, Height, Border,
        Format, Type, Pixels, !IO) :-
    texture_format_to_int(InternalFormat, InternalFormatInt),
    tex_image_2d_2(Target, Level, InternalFormatInt, Width, Height, Border,
        pixel_format_to_int(Format), pixel_type_to_int(Type), Pixels, !IO).

:- pred tex_image_2d_2(texture_target::in, int::in, int::in, int::in,
    int::in, int::in, int::in, int::in, pixel_data::bitmap_ui,
    io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    tex_image_2d_2(Target::in, Level::in, InternalFormat::in,
        Width::in, Height::in, Border::in, Format::in, Type::in,
        Pixels::bitmap_ui, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glTexImage2D((GLenum) Target, Level,
        texture_format_flags[InternalFormat], Width, Height, Border,
        pixel_format_flags[Format], pixel_type_flags[Type], Pixels->elements);
    IO = IO0;
").

% Requires OpenGL 1.2
% tex_image_3d(Target, Level, InternalFormat, Width, Height, Depth, Border,
%         Format, Type, Pixels, !IO) :-
%     texture_target_to_int(Target, TargetInt),
%     texture_format_to_int(InternalFormat, InternalFormatInt),
%     tex_image_3d_2(TargetInt, Level, InternalFormatInt, Width, Height, Depth,
%         Border, pixel_format_to_int(Format), pixel_type_to_int(Type), Pixels,
%         !IO).
% 
% :- pred tex_image_3d_2(int::in, int::in, int::in, int::in, int::in, int::in,
%     int::in, int::in, int::in, pixel_data::bitmap_ui, io::di, io::uo) is det.
% :- pragma foreign_proc("C", 
%     tex_image_3d_2(Target::in, Level::in, InternalFormat::in,
%         Width::in, Height::in, Depth::in, Border::in, Format::in, Type::in,
%         Pixels::in, IO0::di, IO::uo),
%     [will_not_call_mercury, tabled_for_io, promise_pure],
% "
%     glTexImage3D(texture_target_flags[Target], Level,
%         texture_format_flags[InternalFormat], Width, Height, Depth, Border,
%         pixel_format_flags[Format], pixel_type_flags[Type], Pixels);
%     IO = IO0;
% ").

copy_tex_image_1d(Target, Level, InternalFormat, X, Y, Width, Border, !IO) :-
    texture_format_to_int(InternalFormat, InternalFormatInt),
    copy_tex_image_1d_2(Target, Level, InternalFormatInt, X, Y, Width,
        Border, !IO).

:- pred copy_tex_image_1d_2(texture_target::in, int::in, int::in, int::in,
    int::in, int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    copy_tex_image_1d_2(Target::in, Level::in, InternalFormat::in,
        X::in, Y::in, Width::in, Border::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glCopyTexImage1D((GLenum) Target, Level,
        texture_format_flags[InternalFormat], X, Y, Width, Border);
    IO = IO0;
").

copy_tex_image_2d(Target, Level, InternalFormat, X, Y, Width, Height, Border,
        !IO) :-
    texture_format_to_int(InternalFormat, InternalFormatInt),
    copy_tex_image_2d_2(Target, Level, InternalFormatInt, X, Y,
        Width, Height, Border, !IO).

:- pred copy_tex_image_2d_2(texture_target::in, int::in, int::in, int::in,
    int::in, int::in, int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    copy_tex_image_2d_2(Target::in, Level::in, InternalFormat::in,
        X::in, Y::in, Width::in, Height::in, Border::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glCopyTexImage2D((GLenum) Target, Level,
        texture_format_flags[InternalFormat], X, Y, Width, Height, Border);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Fog
%

:- pragma foreign_enum("C", fog_mode/0, [
    linear - "GL_LINEAR",
    exp    - "GL_EXP",
    exp2   - "GL_EXP2"
]).

fog(fog_mode(Mode), !IO) :-
    fog_mode(Mode, !IO).
fog(fog_density(Density), !IO) :-
    fog_density(Density, !IO).
fog(fog_start(Start), !IO) :-
    fog_start(Start, !IO).
fog(fog_end(End), !IO) :-
    fog_end(End, !IO).
fog(fog_index(Index), !IO) :-
    fog_index(Index, !IO).
fog(fog_color(R, G, B, A), !IO) :-
    fog_color(R, G, B, A, !IO).

:- pred fog_mode(fog_mode::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    fog_mode(M::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFogi(GL_FOG_MODE, (GLint) M);
    IO = IO0;
").

:- pred fog_density(float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    fog_density(P::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFogf(GL_FOG_DENSITY, (GLfloat) P);
    IO = IO0;
").

:- pred fog_start(float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    fog_start(P::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFogf(GL_FOG_START, (GLfloat) P);
    IO = IO0;
").

:- pred fog_end(float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    fog_end(P::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFogf(GL_FOG_END, (GLfloat) P);
    IO = IO0;
").

:- pred fog_index(float::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    fog_index(I::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFogf(GL_FOG_INDEX, (GLfloat) I);
    IO = IO0;
").

:- pred fog_color(float::in, float::in, float::in, float::in,
    io::di, io::uo) is det.
:- pragma foreign_proc("C",
    fog_color(R::in, G::in, B::in, A::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat fog_color[] = {R, G, B, A};
    
    glFogfv(GL_FOG_COLOR, fog_color); 
    IO = IO0;
").

:- pragma foreign_proc("C", 
    get_fog_mode(Mode::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLint mode;

    glGetIntegerv(GL_FOG_MODE, &mode);
    Mode = (MR_Integer) mode;
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Per-fragment operations
%

:- pragma foreign_proc("C", 
    scissor(X::in, Y::in, Width::in, Height::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glScissor((GLint)X, (GLint)Y, (GLsizei)Width, (GLsizei)Height);
    IO = IO0;
").

:- pragma foreign_enum("C", test_func/0, [
    never       - "GL_NEVER",
    always      - "GL_ALWAYS",
    less        - "GL_LESS",
    lequal      - "GL_LEQUAL",
    equal       - "GL_EQUAL",
    gequal      - "GL_GEQUAL",
    greater     - "GL_GREATER",
    not_equal   - "GL_NOTEQUAL"
]).

:- pragma foreign_proc("C", 
    alpha_func(TestFunc::in, Ref::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glAlphaFunc((GLenum) TestFunc, (GLclampf) Ref);
    IO = IO0;

").

:- pragma foreign_proc("C",
    stencil_func(TestFunc::in, Ref::in, Mask::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glStencilFunc((GLenum) TestFunc, (GLint) Ref, (GLuint) Mask);
    IO = IO0;
").

:- pragma foreign_enum("C", stencil_op/0, [
    keep        - "GL_KEEP",
    zero        - "GL_ZERO",
    replace     - "GL_REPLACE",
    incr        - "GL_INCR",
    decr        - "GL_DECR",
    invert      - "GL_INVERT"
]).    

:- pragma foreign_proc("C", 
    stencil_op(Fail::in, ZFail::in, ZPass::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure, 
        does_not_affect_liveness], 
"
    glStencilOp((GLenum) Fail, (GLenum) ZFail, (GLenum) ZPass);
    IO = IO0;
").

:- pragma foreign_proc("C",
    depth_func(TestFunc::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glDepthFunc((GLenum) TestFunc);
    IO = IO0;
").

:- pragma foreign_enum("C", blend_src/0, [
    zero                - "GL_ZERO",
    one                 - "GL_ONE",
    dst_color           - "GL_DST_COLOR",
    one_minus_dst_color - "GL_ONE_MINUS_DST_COLOR",
    src_alpha           - "GL_SRC_ALPHA",
    one_minus_src_alpha - "GL_ONE_MINUS_SRC_ALPHA",
    dst_alpha           - "GL_DST_ALPHA",
    one_minus_dst_alpha - "GL_ONE_MINUS_DST_ALPHA",
    src_alpha_saturate  - "GL_SRC_ALPHA_SATURATE"
]).

:- pragma foreign_enum("C", blend_dst/0, [
    zero                - "GL_ZERO",
    one                 - "GL_ONE",
    src_color           - "GL_SRC_COLOR",
    one_minus_src_color - "GL_ONE_MINUS_SRC_COLOR",
    src_alpha           - "GL_SRC_ALPHA",
    one_minus_src_alpha - "GL_ONE_MINUS_SRC_ALPHA",
    dst_alpha           - "GL_DST_ALPHA",
    one_minus_dst_alpha - "GL_ONE_MINUS_DST_ALPHA"
]).

:- pragma foreign_proc("C", 
    blend_func(Src::in, Dst::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glBlendFunc((GLenum) Src, (GLenum) Dst);
    IO = IO0;
").

:- pragma foreign_enum("C", logic_op/0, [
    clear         - "GL_CLEAR",
    (and)         - "GL_AND",
    and_reverse   - "GL_AND_REVERSE",
    copy          - "GL_COPY",
    and_inverted  - "GL_AND_INVERTED",
    no_op         - "GL_NOOP",
    xor           - "GL_XOR",
    (or)          - "GL_OR",
    nor           - "GL_NOR",
    equiv         - "GL_EQUIV",
    invert        - "GL_INVERT",
    or_reverse    - "GL_OR_REVERSE",
    copy_inverted - "GL_COPY_INVERTED",
    or_inverted   - "GL_OR_INVERTED",
    nand          - "GL_NAND",
    set           - "GL_SET"
]).

:- pragma foreign_proc("C", 
    logic_op(LogicOp::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure, 
        does_not_affect_liveness], 
"
    glLogicOp((GLenum) LogicOp);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Whole framebuffer operations
%

:- pred buffer_to_int_and_offset(draw_buffer::in, int::out, int::out) is det.

buffer_to_int_and_offset(none, 0, 0).   
buffer_to_int_and_offset(front_left, 1, 0).
buffer_to_int_and_offset(front_right, 2, 0).
buffer_to_int_and_offset(back_left, 3, 0).
buffer_to_int_and_offset(back_right, 4, 0).
buffer_to_int_and_offset(front, 5, 0).
buffer_to_int_and_offset(back, 6, 0).
buffer_to_int_and_offset(left, 7, 0).
buffer_to_int_and_offset(right, 8, 0).
buffer_to_int_and_offset(front_and_back, 9, 0).
buffer_to_int_and_offset(aux(I), 10, I).    

:- pragma foreign_decl("C", "
    extern const GLenum buffer_flags[];
").

:- pragma foreign_code("C", "
    const GLenum buffer_flags[] = {
        GL_NONE,
        GL_FRONT_LEFT,
        GL_FRONT_RIGHT,
        GL_BACK_LEFT,
        GL_BACK_RIGHT,
        GL_FRONT,
        GL_BACK,
        GL_LEFT,
        GL_RIGHT,
        GL_FRONT_AND_BACK,
        GL_AUX0
    };
").

draw_buffer(Buffer, !IO) :-
    buffer_to_int_and_offset(Buffer, Flag, Offset),
    draw_buffer_2(Flag, Offset, !IO).

:- pred draw_buffer_2(int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    draw_buffer_2(BufferFlag::in, Offset::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glDrawBuffer(buffer_flags[BufferFlag] + Offset);
    IO = IO0;
").

:- pragma foreign_proc("C",
    index_mask(I::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glIndexMask((GLuint) I);
    IO = IO0;
").

color_mask(A, B, C, D, !IO) :-
    color_mask_2(bool_to_int(A), bool_to_int(B),
        bool_to_int(C), bool_to_int(D), !IO).

:- pred color_mask_2(int::in, int::in, int::in, int::in, io::di, io::uo)
    is det.
:- pragma foreign_proc("C",
    color_mask_2(A::in, B::in, C::in, D::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glColorMask((GLboolean) A, (GLboolean) B, (GLboolean) C, (GLboolean) D);
    IO = IO0;
").

depth_mask(Bool, !IO) :-
    depth_mask_2(bool_to_int(Bool), !IO).

:- pred depth_mask_2(int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    depth_mask_2(M::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glDepthMask((GLboolean) M);
    IO = IO0;
").

:- pragma foreign_proc("C",
    stencil_mask(M::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness], 
"
    glStencilMask((GLuint) M);
    IO = IO0;
").

clear(BitList, !IO) :-
    Mask = list.foldr((\/), list.map(buffer_bit_to_bit, BitList), 0),
    clear2(Mask, !IO).

:- func buffer_bit_to_bit(buffer_bit) = int.

buffer_bit_to_bit(Flag) = lookup_buffer_bit(buffer_bit_to_int(Flag)).

:- func buffer_bit_to_int(buffer_bit) = int.

buffer_bit_to_int(color)   = 0.
buffer_bit_to_int(depth)   = 1.
buffer_bit_to_int(stencil) = 2.
buffer_bit_to_int(accum)   = 3.

% XXX Remove the static data from lookup_buffer_bit/1.
:- pragma no_inline(lookup_buffer_bit/1).
:- func lookup_buffer_bit(int) = int.

:- pragma foreign_proc("C",
    lookup_buffer_bit(F::in) = (B::out),
    [will_not_call_mercury, promise_pure, does_not_affect_liveness], 
"
    static GLbitfield a[] = {
        GL_COLOR_BUFFER_BIT,
        GL_DEPTH_BUFFER_BIT,
        GL_STENCIL_BUFFER_BIT,
        GL_ACCUM_BUFFER_BIT
    };

    B = a[F];
").

:- pred clear2(int::in, io::di, io::uo) is det.

:- pragma foreign_proc("C",
    clear2(Mask::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glClear(Mask);
    IO = IO0;
").

:- pragma foreign_proc("C",
    clear_color(R::in, G::in, B::in, A::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glClearColor((GLclampf) R, (GLclampf) G, (GLclampf) B, (GLclampf) A);
    IO = IO0;
").

:- pragma foreign_proc("C",
    clear_index(I::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glClearIndex((GLfloat) I);
    IO = IO0;
").

:- pragma foreign_proc("C",
    clear_depth(I::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glClearDepth((GLfloat) I);
    IO = IO0;
").

:- pragma foreign_proc("C",
    clear_stencil(I::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glClearStencil((GLint) I);
    IO = IO0;
").

:- pragma foreign_proc("C", 
    clear_accum(R::in, G::in, B::in, A::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glClearAccum((GLfloat) R, (GLfloat) G, (GLfloat) B, (GLfloat) A);
    IO = IO0;
").

:- pragma foreign_enum("C", accum_op/0, [
    accum  - "GL_ACCUM",
    load   - "GL_LOAD",
    return - "GL_RETURN",
    mult   - "GL_MULT",
    add    - "GL_ADD"
]).

:- pragma foreign_proc("C",
    accum(AccumOp::in, Value::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glAccum((GLenum) AccumOp, Value);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Evaluators
%

map1(Target, U1, U2, curve(Stride, Order, CtrlPoints), !IO) :-
    ( target_matches_stride_1d(Target, Stride) ->   
        map1_2(eval_1d_to_int(Target), U1, U2, Stride, Order, 
            CtrlPoints, !IO)
    ;
        throw(software_error("mogl.map_1/6: bad data dimension."))
    ).

:- pred target_matches_stride_1d(eval_target::in, int::in) is semidet.

target_matches_stride_1d(vertex_3, 3).
target_matches_stride_1d(vertex_4, 4).
target_matches_stride_1d(index, 1).
target_matches_stride_1d(color_4, 4).
target_matches_stride_1d(normal, 3).
target_matches_stride_1d(texture_coord_1, 1).
target_matches_stride_1d(texture_coord_2, 2).
target_matches_stride_1d(texture_coord_3, 3).
target_matches_stride_1d(texture_coord_4, 4).

unsafe_map1(Target, U1, U2, curve(Stride, Order, CtrlPoints), !IO) :-
    map1_2(eval_1d_to_int(Target), U1, U2, Stride, Order,
        CtrlPoints, !IO).

unsafe_map1(Target, U1, U2, MaybeAltStride, MaybeAltOrder,
        curve(AutoStride, AutoOrder, CtrlPoints), !IO) :-
    Stride = ( MaybeAltStride = yes(Stride0) -> Stride0 ; AutoStride ),
    Order  = ( MaybeAltOrder  = yes(Order0)  -> Order0  ; AutoOrder  ),
    map1_2(eval_1d_to_int(Target), U1, U2, Stride, Order, CtrlPoints,
        !IO).

:- pred map1_2(int::in, float::in, float::in, int::in, int::in,
    ctrl_points::in, io::di, io::uo) is det.

:- pragma foreign_proc("C",
    map1_2(CtrlFlagIndex::in, U1::in, U2::in, Stride::in, Order::in,
        Points::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glMap1f(control_flag_flags[CtrlFlagIndex], U1, U2,
            Stride, Order, (const GLfloat *) Points); 
    } else {
        glMap1d(control_flag_flags[CtrlFlagIndex], U1, U2,
            Stride, Order, (const GLdouble *) Points);
    }
    
    IO = IO0;
").

    % NOTE: we just reuse the control_flag_flags array
    % for these, which is why the indicies are not what
    % you might expect.
:- func eval_1d_to_int(eval_target) = int.

eval_1d_to_int(vertex_3) = 25.
eval_1d_to_int(vertex_4) = 26.
eval_1d_to_int(index)    = 27.
eval_1d_to_int(color_4)  = 28.
eval_1d_to_int(normal)   = 29.
eval_1d_to_int(texture_coord_1) = 30.
eval_1d_to_int(texture_coord_2) = 31.
eval_1d_to_int(texture_coord_3) = 32. 
eval_1d_to_int(texture_coord_4) = 33.

:- type curve_points
    --->    curve(
                stride          :: int, 
                order           :: int,
                curve_ctrl_pts  :: ctrl_points
            ).

:- type ctrl_points.
:- pragma foreign_type("C", ctrl_points, "const GLvoid *",
    [can_pass_as_mercury_type]). 

make_curve(one(Verticies)) = curve(1, Order, CtrlPts) :-
    Order   = list.length(Verticies),
    CtrlPts = pack_ctrl_pts1_1d(Order, Verticies).
make_curve(two(Verticies)) = curve(2, Order, CtrlPts) :-
    Order    = list.length(Verticies),
    CtrlPts = pack_ctrl_pts2_1d(Order, Verticies).
make_curve(three(Verticies)) = curve(3, Order, CtrlPts) :-
    Order   = list.length(Verticies),
    CtrlPts = pack_ctrl_pts3_1d(Order, Verticies).
make_curve(four(Verticies)) = curve(4, Order, CtrlPts) :-
    Order   = list.length(Verticies),
    CtrlPts = pack_ctrl_pts4_1d(Order, Verticies).  


:- pragma foreign_decl("C", "
/* 
** The following macros create and manipulate control point arrays.
** These macros abstract away the differences that occur
** when we use arrays of GLfloat as opposed to GLdouble (which in turn
** depends upon whether MR_Float is single or double-precision).
*/ 

/* 
** The MOGL_make_ctrl_point_array() macro allocates an array large
** enough to hold `size' control points of the specified dimension.
*/
#define MOGL_make_ctrl_point_array(array, size, dimension)      \
    do {                                \
        if (sizeof(MR_Float) == sizeof(GLfloat)) {      \
            array = MR_GC_NEW_ARRAY(GLfloat,        \
                (size) * (dimension));          \
        } else {                        \
            array = MR_GC_NEW_ARRAY(GLdouble,       \
                (size) * (dimension));          \
        }                           \
    } while(0)

/*
** The MGOGL_set_ctrl_point() macro sets the value of a particular
** index in a control point array.
*/ 
#define MOGL_set_ctrl_point(array, address, value)          \
    do {                                    \
        if (sizeof(MR_Float) == sizeof(GLfloat)) {      \
            ((GLfloat *) (array))[(address)] = (value); \
        } else {                        \
            ((GLdouble *) (array))[(address)] = (value);    \
        }                           \
    } while(0)      
").

:- func pack_ctrl_pts1_1d(int, list(float)) = ctrl_points.
:- pragma foreign_proc("C",
    pack_ctrl_pts1_1d(Order::in, Verticies::in) = (Points::out),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    int i = 0;

    MOGL_make_ctrl_point_array(Points, Order, 1);
    
    while (!MR_list_is_empty(Verticies)) {

        MOGL_set_ctrl_point(Points, i, MR_list_head(Verticies));    
        Verticies = MR_list_tail(Verticies);
        i++;
    }           
").

:- func pack_ctrl_pts2_1d(int, list({float, float})) = ctrl_points.
:- pragma foreign_proc("C",
    pack_ctrl_pts2_1d(Order::in, Verticies::in) = (Points::out),
    [may_call_mercury, tabled_for_io, promise_pure, terminates,
        will_not_throw_exception],
"
    MR_Float x, y;
    int i = 0;

    MOGL_make_ctrl_point_array(Points, Order, 2);
    
    while (!MR_list_is_empty(Verticies)) {
        
        MOGL_deconstruct_double(MR_list_head(Verticies), &x, &y);

        MOGL_set_ctrl_point(Points, i, x);
        MOGL_set_ctrl_point(Points, i + 1, y);

        Verticies = MR_list_tail(Verticies);
        i += 2;
    }
").

:- func pack_ctrl_pts3_1d(int, list({float, float, float})) = ctrl_points.
:- pragma foreign_proc("C",
    pack_ctrl_pts3_1d(Order::in, Verticies::in) = (Points::out),
    [may_call_mercury, tabled_for_io, promise_pure, terminates,
        will_not_throw_exception],
"
    MR_Float x, y, z;
    int i = 0;

    MOGL_make_ctrl_point_array(Points, Order, 3);

    while (!MR_list_is_empty(Verticies)) {
        
        MOGL_deconstruct_triple(MR_list_head(Verticies), &x, &y, &z);

        MOGL_set_ctrl_point(Points, i,     x);
        MOGL_set_ctrl_point(Points, i + 1, y);
        MOGL_set_ctrl_point(Points, i + 2, z);
        
        Verticies = MR_list_tail(Verticies);
        i += 3; 
    }
").


:- func pack_ctrl_pts4_1d(int, list({float, float, float, float}))
    = ctrl_points.
:- pragma foreign_proc("C",
    pack_ctrl_pts4_1d(Order::in, Verticies::in) = (Points::out),
    [may_call_mercury, tabled_for_io, promise_pure, terminates,
        will_not_throw_exception],

"
    MR_Float x, y, z, w;
    int i = 0;

    MOGL_make_ctrl_point_array(Points, Order, 4);

    while(!MR_list_is_empty(Verticies)) {

        MOGL_deconstruct_quadruple(MR_list_head(Verticies),
            &x, &y, &z, &w);
    
        MOGL_set_ctrl_point(Points, i, x);
        MOGL_set_ctrl_point(Points, i + 1, y);
        MOGL_set_ctrl_point(Points, i + 2, z);
        MOGL_set_ctrl_point(Points, i + 3, w);
        
        Verticies = MR_list_tail(Verticies);
        i += 4;
    }
").

:- pragma foreign_export("C", deconstruct_double(in, out, out), 
    "MOGL_deconstruct_double").
:- pred deconstruct_double({float, float}::in, float::out, float::out) is det.

deconstruct_double({A, B}, A, B).

:- pragma foreign_export("C", deconstruct_triple(in, out, out, out),
    "MOGL_deconstruct_triple").
:- pred deconstruct_triple({float, float, float}::in, float::out, float::out,
    float::out) is det.

deconstruct_triple({A, B, C}, A, B, C).

:- pragma foreign_export("C",
    deconstruct_quadruple(in, out, out, out, out),
    "MOGL_deconstruct_quadruple").
:- pred deconstruct_quadruple({float, float, float, float}::in, 
    float::out, float::out, float::out, float::out) is det.

deconstruct_quadruple({A, B, C, D}, A, B, C, D).

:- type surface_points
    --->    surface(
                ustride :: int,
                uorder  :: int,
                vstride :: int,
                vorder  :: int,
                surface_ctrl_points :: ctrl_points
            ).  

:- pragma foreign_proc("C",
    eval_coord1(U::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glEvalCoord1f((GLfloat) U);
    } else {
        glEvalCoord1d((GLdouble) U);
    }
    IO = IO0;
").
    
:- pragma foreign_proc("C",
    eval_coord2(U::in, V::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glEvalCoord2f((GLfloat) U, (GLfloat) V);
    } else {
        glEvalCoord2d((GLdouble) U, (GLdouble) V);
    }
    IO = IO0;
").

:- pragma foreign_enum("C", mesh_mode/0, [
    point - "GL_POINT",
    line  - "GL_LINE",
    fill  - "GL_FILL"
]).

:- pragma foreign_proc("C",
    eval_mesh1(MeshFlag::in(mesh_mode_1d), P1::in, P2::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEvalMesh1((GLenum) MeshFlag, (GLint) P1, (GLint) P2);
    IO = IO0;
").

:- pragma foreign_proc("C",
    eval_mesh2(MeshFlag::in, P1::in, P2::in, Q1::in, Q2::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEvalMesh2((GLenum) MeshFlag, P1, P2, Q1, Q2);
    IO = IO0;
").

:- pragma foreign_proc("C",
    map_grid1(N::in, U1::in, U2::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glMapGrid1f(N, U1, U2);
    } else {
        glMapGrid1d(N, U1, U2);
    }
    IO = IO0;
").

:- pragma foreign_proc("C",
    eval_point1(I::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEvalPoint1((GLint) I);
    IO = IO0;
").

:- pragma foreign_proc("C",
    map_grid2(Nu::in, U1::in, U2::in, Nv::in, V1::in, V2::in,
        IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (sizeof(MR_Float) == sizeof(GLfloat)) {
        glMapGrid2f(Nu, U1, U2, Nv, V1, V2);
    } else {
        glMapGrid2d(Nu, U1, U2, Nv, V1, V2);
    }
    IO = IO0;
").

:- pragma foreign_proc("C",
    eval_point2(I::in, J::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEvalPoint2((GLint) I, (GLint) J);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Feedback
%

:- pragma foreign_proc("C",
    pass_through(Token::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPassThrough((GLfloat) Token);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Selection
%

:- pragma foreign_proc("C",
    init_names(IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glInitNames();
    IO = IO0;
").

:- pragma foreign_proc("C",
    pop_name(IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPopName();
    IO = IO0;
").

:- pragma foreign_proc("C",
    push_name(Name::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure, 
        does_not_affect_liveness],
"
    glPushName((GLuint)Name);
    IO = IO0;
").

:- pragma foreign_proc("C",
    load_name(Name::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glLoadName((GLuint)Name);
    IO = IO0;
").

:- pragma foreign_enum("C", render_mode/0, [
    render   - "GL_RENDER",
    select   - "GL_SELECT",
    feedback - "GL_FEEDBACK"
]).

:- pragma foreign_proc("C", 
    render_mode(RenderMode::in, Output::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure, 
        does_not_affect_liveness],
"
    Output = (MR_Integer) glRenderMode((GLenum) RenderMode);
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Display lists
% 

:- pragma foreign_enum("C", display_list_mode/0, [
    compile             - "GL_COMPILE",
    compile_and_execute - "GL_COMPILE_AND_EXECUTE"
]).

:- pragma foreign_proc("C",
    new_list(N::in, M::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glNewList((GLuint) N, (GLenum) M);
    IO = IO0;
").

:- pragma foreign_proc("C",
    end_list(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEndList();
    IO = IO0;
").

:- pragma foreign_proc("C",
    call_list(N::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glCallList((GLuint) N);
    IO = IO0;
").

:- pragma foreign_proc("C",
    gen_lists(N::in, M::out, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    M = (MR_Integer) glGenLists((GLsizei) N);
    IO = IO0;
").

:- pragma foreign_proc("C",
    delete_lists(N::in, M::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glDeleteLists((GLuint) N, (GLsizei) M);
    IO = IO0;
").

:- pragma foreign_proc("C",
    is_list(L::in, R::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (glIsList((GLuint) L)) {
        R = MR_YES;
    } else {
        R = MR_NO;
    }
    IO = IO0;
").

:- pragma foreign_proc("C",
    list_base(Base::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glListBase((GLuint) Base);
    IO = IO0;
").

%------------------------------------------------------------------------------%

:- pragma foreign_proc("C",
    flush(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFlush();
    IO = IO0;
    assert(glGetError() == GL_NO_ERROR);
").

:- pragma foreign_proc("C",
    finish(IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glFinish();
    IO = IO0;
    assert(glGetError() == GL_NO_ERROR);
").

%------------------------------------------------------------------------------%

% NOTE: the ordering of these control flags is important.  The code for
% handling evaluator targets depends upon this ordering.

:- pred control_flag_to_int_and_offset(control_flag::in, int::out, int::out)
    is det.

control_flag_to_int_and_offset(alpha_test,           0,  0).
control_flag_to_int_and_offset(auto_normal,          1,  0).
control_flag_to_int_and_offset(blend,                2,  0).
control_flag_to_int_and_offset(clip_plane(Plane),    3,  Plane).
control_flag_to_int_and_offset(color_logic_op,       4,  0).
control_flag_to_int_and_offset(color_material,       5,  0).
control_flag_to_int_and_offset(cull_face,            6,  0).
control_flag_to_int_and_offset(depth_test,           7,  0).
control_flag_to_int_and_offset(dither,               8,  0).
control_flag_to_int_and_offset(fog,                  9,  0).
control_flag_to_int_and_offset(index_logic_op,       10, 0).
control_flag_to_int_and_offset(light(LightNo),       11, LightNo).
control_flag_to_int_and_offset(lighting,             12, 0).
control_flag_to_int_and_offset(line_smooth,          13, 0).
control_flag_to_int_and_offset(line_stipple,         14, 0).
control_flag_to_int_and_offset(normalize,            15, 0).
control_flag_to_int_and_offset(point_smooth,         16, 0).
control_flag_to_int_and_offset(polygon_offset_fill,  17, 0).
control_flag_to_int_and_offset(polygon_offset_line,  18, 0).
control_flag_to_int_and_offset(polygon_offset_point, 19, 0).
control_flag_to_int_and_offset(polygon_stipple,      20, 0).
control_flag_to_int_and_offset(scissor_test,         21, 0).
control_flag_to_int_and_offset(stencil_test,         22, 0).
control_flag_to_int_and_offset(texture_1d,           23, 0).
control_flag_to_int_and_offset(texture_2d,           24, 0).
control_flag_to_int_and_offset(map1_vertex_3,        25, 0).    
control_flag_to_int_and_offset(map1_vertex_4,        26, 0).
control_flag_to_int_and_offset(map1_index,           27, 0).
control_flag_to_int_and_offset(map1_color_4,         28, 0).
control_flag_to_int_and_offset(map1_normal,          29, 0).
control_flag_to_int_and_offset(map1_texture_coord_1, 30, 0).
control_flag_to_int_and_offset(map1_texture_coord_2, 31, 0).
control_flag_to_int_and_offset(map1_texture_coord_3, 32, 0).
control_flag_to_int_and_offset(map1_texture_coord_4, 33, 0).
control_flag_to_int_and_offset(map2_vertex_3,        34, 0).
control_flag_to_int_and_offset(map2_vertex_4,        35, 0).
control_flag_to_int_and_offset(map2_index,           36, 0).
control_flag_to_int_and_offset(map2_color_4,         37, 0).
control_flag_to_int_and_offset(map2_normal,          38, 0).
control_flag_to_int_and_offset(map2_texture_coord_1, 39, 0).
control_flag_to_int_and_offset(map2_texture_coord_2, 40, 0).
control_flag_to_int_and_offset(map2_texture_coord_3, 41, 0).
control_flag_to_int_and_offset(map2_texture_coord_4, 42, 0).    

:- pragma foreign_decl("C", "
    extern const GLenum control_flag_flags[];
").

:- pragma foreign_code("C", "
    const GLenum control_flag_flags[] = {
        GL_ALPHA_TEST,
        GL_AUTO_NORMAL,
        GL_BLEND,
        GL_CLIP_PLANE0,
        GL_COLOR_LOGIC_OP,
        GL_COLOR_MATERIAL,
        GL_CULL_FACE,
        GL_DEPTH_TEST,
        GL_DITHER,
        GL_FOG,
        GL_INDEX_LOGIC_OP,
        GL_LIGHT0,
        GL_LIGHTING,
        GL_LINE_SMOOTH,
        GL_LINE_STIPPLE,
        GL_NORMALIZE,
        GL_POINT_SMOOTH,
        GL_POLYGON_OFFSET_FILL,
        GL_POLYGON_OFFSET_LINE,
        GL_POLYGON_OFFSET_POINT,
        GL_POLYGON_STIPPLE,
        GL_SCISSOR_TEST,
        GL_STENCIL_TEST,
        GL_TEXTURE_1D,
        GL_TEXTURE_2D,
        GL_MAP1_VERTEX_3,
        GL_MAP1_VERTEX_4,
        GL_MAP1_INDEX,
        GL_MAP1_COLOR_4,
        GL_MAP1_NORMAL,
        GL_MAP1_TEXTURE_COORD_1,
        GL_MAP1_TEXTURE_COORD_2,
        GL_MAP1_TEXTURE_COORD_3,
        GL_MAP1_TEXTURE_COORD_4,
        GL_MAP2_VERTEX_3,
        GL_MAP2_VERTEX_4,
        GL_MAP2_INDEX,
        GL_MAP2_COLOR_4,
        GL_MAP2_NORMAL,
        GL_MAP2_TEXTURE_COORD_1,
        GL_MAP2_TEXTURE_COORD_2,
        GL_MAP2_TEXTURE_COORD_3,
        GL_MAP2_TEXTURE_COORD_4
    };
").

enable(Flag, !IO) :-
    control_flag_to_int_and_offset(Flag, Int, Offset),
    enable_2(Int, Offset, !IO).

:- pred enable_2(int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    enable_2(FlagVal::in, Offset::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glEnable(control_flag_flags[FlagVal] + Offset);
    IO = IO0;
").

disable(Flag, !IO) :-
    control_flag_to_int_and_offset(Flag, Int, Offset),
    disable_2(Int, Offset, !IO).

:- pred disable_2(int::in, int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    disable_2(FlagVal::in, Offset::in, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glDisable(control_flag_flags[FlagVal] + Offset);
    IO = IO0;
").

is_enabled(Flag, IsEnabled, !IO) :-
    control_flag_to_int_and_offset(Flag, Int, Offset),
    is_enabled_2(Int, Offset, IsEnabled, !IO).

:- pred is_enabled_2(int::in, int::in, bool::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    is_enabled_2(FlagVal::in, Offset::in, R::out, IO0::di, IO::uo), 
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    if (glIsEnabled(control_flag_flags[FlagVal] + Offset)) {
        R = MR_YES;
    } else {
        R = MR_NO;
    }
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Hints
%

:- pragma foreign_enum("C", hint_target/0, [
    perspective_correction - "GL_PERSPECTIVE_CORRECTION_HINT",
    point_smooth           - "GL_POINT_SMOOTH_HINT",
    line_smooth            - "GL_LINE_SMOOTH",
    polygon_smooth         - "GL_POLYGON_SMOOTH",
    fog                    - "GL_FOG_HINT"
]).

:- pragma foreign_enum("C", hint_mode/0, [
    fastest     - "GL_FASTEST",
    nicest      - "GL_NICEST",
    do_not_care - "GL_DONT_CARE"
]).
    
:- pragma foreign_proc("C",
    hint(HintTarget::in, HintMode::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure, 
        does_not_affect_liveness],
"
    glHint((GLenum) HintTarget, (GLenum) HintMode);
    IO = IO0;
").

:- pragma foreign_proc("C",
    get_hint(HintTarget::in, HintMode::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLint mode;
    glGetIntegerv((GLenum) HintTarget, &mode);
    HintMode = (MR_Integer) mode;
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% State and state requests
%

get_clip_plane(I, clip(X, Y, Z, W), !IO) :-
    get_clip_plane_2(I, X, Y, Z, W, !IO).

:- pred get_clip_plane_2(int::in, float::out, float::out, float::out,   
    float::out, io::di, io::uo) is det.
:- pragma foreign_proc("C", 
    get_clip_plane_2(I::in, X::out, Y::out, Z::out, W::out, IO0::di,
        IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLdouble equation[4];
    
    assert(GL_CLIP_PLANE0 + I < GL_MAX_CLIP_PLANES);
    
    glGetClipPlane(GL_CLIP_PLANE0 + I, equation);

    X = (MR_Float) equation[0];
    Y = (MR_Float) equation[1];
    Z = (MR_Float) equation[2];
    W = (MR_Float) equation[3];

    IO = IO0;
").

:- pragma foreign_enum("C", single_boolean_state/0, [
    current_raster_position_valid - "GL_CURRENT_RASTER_POSITION_VALID",
    depth_writemask               - "GL_DEPTH_WRITEMASK",
    double_buffer                 - "GL_DOUBLEBUFFER",
    edge_flag                     - "GL_EDGE_FLAG",
    index_mode                    - "GL_INDEX_MODE",
    light_model_local_viewer      - "GL_LIGHT_MODEL_LOCAL_VIEWER",
    light_model_two_side          - "GL_LIGHT_MODEL_TWO_SIDE",
    map_color                     - "GL_MAP_COLOR",
    map_stencil                   - "GL_MAP_STENCIL",
    pack_lsb_first                - "GL_PACK_LSB_FIRST",
    pack_swap_bytes               - "GL_PACK_SWAP_BYTES",
    rgba_mode                     - "GL_RGBA_MODE",
    stereo                        - "GL_STEREO",
    unpack_lsb_first              - "GL_UNPACK_LSB_FIRST",
    unpack_swap_bytes             - "GL_UNPACK_SWAP_BYTES"
]).

:- pragma foreign_proc("C",
    get_boolean(Param::in, Value::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLboolean value;

    glGetBooleanv((GLenum) Param, &value);
    
    if (value == GL_TRUE) {
        Value = MR_YES;
    } else {
        Value = MR_NO;
    }

    IO = IO0;
").

:- pragma foreign_enum("C", quad_boolean_state/0, [
    color_writemask - "GL_COLOR_WRITEMASK"
]).

:- pragma foreign_proc("C",
    get_boolean(Param::in, V0::out, V1::out, V2::out, V3::out,
        IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLboolean values[4];

    glGetBooleanv((GLenum) Param, values);

    if (values[0] == GL_TRUE) {
        V0 = MR_YES;
    } else {
        V0 = MR_NO;
    }
    
    if (values[1] == GL_TRUE) {
        V1 = MR_YES;
    } else {
        V1 = MR_NO;
    }
    
    if (values[2] == GL_TRUE) {
        V2 = MR_YES;
    } else {
        V2 = MR_NO;
    }
    
    if (values[3] == GL_TRUE) {
        V3 = MR_YES;
    } else {
        V3 = MR_NO;
    }

    IO = IO0;
").

:- pragma foreign_decl("C", "
    extern const GLenum single_integer_state_flags[];
").

:- pragma foreign_code("C", "
    const GLenum single_integer_state_flags[] = {
        GL_ACCUM_ALPHA_BITS,
        GL_ACCUM_BLUE_BITS,
        GL_ACCUM_GREEN_BITS,
        GL_ACCUM_RED_BITS,
        GL_ALPHA_BITS,
        GL_ALPHA_TEST_REF,
        GL_ATTRIB_STACK_DEPTH,
        GL_AUX_BUFFERS,
        GL_BLUE_BITS,
        GL_CLIENT_ATTRIB_STACK_DEPTH,
        GL_COLOR_ARRAY_SIZE,
        GL_COLOR_ARRAY_STRIDE,
        GL_DEPTH_BITS,
        GL_DEPTH_CLEAR_VALUE,
        GL_EDGE_FLAG_ARRAY_STRIDE,
        GL_FEEDBACK_BUFFER_SIZE,
        GL_GREEN_BITS,
        GL_INDEX_ARRAY_STRIDE,
        GL_INDEX_BITS,
        GL_INDEX_OFFSET,
        GL_INDEX_OFFSET,
        GL_INDEX_SHIFT,
        GL_LINE_STIPPLE_REPEAT,
        GL_LIST_BASE,
        GL_LIST_INDEX,
        GL_MAX_ATTRIB_STACK_DEPTH,
        GL_MAX_CLIENT_ATTRIB_STACK_DEPTH,
        GL_MAX_CLIP_PLANES,
        GL_MAX_EVAL_ORDER,
        GL_MAX_LIGHTS,
        GL_MAX_LIST_NESTING,
        GL_MAX_MODELVIEW_STACK_DEPTH,
        GL_MAX_NAME_STACK_DEPTH,
        GL_MAX_PIXEL_MAP_TABLE,
        GL_MAX_PROJECTION_STACK_DEPTH,
        GL_MAX_TEXTURE_SIZE,
        GL_MAX_TEXTURE_STACK_DEPTH,
        GL_NAME_STACK_DEPTH,
        GL_NORMAL_ARRAY_STRIDE,
        GL_PACK_ALIGNMENT,
        GL_PACK_ROW_LENGTH,
        GL_PACK_SKIP_ROWS,
        GL_PROJECTION_STACK_DEPTH,
        GL_RED_BITS,
        GL_SELECTION_BUFFER_SIZE,
        GL_STENCIL_BITS,
        GL_STENCIL_CLEAR_VALUE,
        GL_STENCIL_REF,
        GL_SUBPIXEL_BITS,
        GL_TEXTURE_COORD_ARRAY_SIZE,
        GL_TEXTURE_COORD_ARRAY_STRIDE,
        GL_TEXTURE_STACK_DEPTH,
        GL_UNPACK_ALIGNMENT,
        GL_UNPACK_SKIP_PIXELS,
        GL_UNPACK_SKIP_ROWS,
        GL_VERTEX_ARRAY_SIZE,
        GL_VERTEX_ARRAY_STRIDE
    };
").

:- func single_integer_state_to_int(single_integer_state) = int.

single_integer_state_to_int(accum_alpha_bits) = 0.
single_integer_state_to_int(accum_blue_bits) = 1.
single_integer_state_to_int(accum_green_bits) = 2.
single_integer_state_to_int(accum_red_bits) = 3.
single_integer_state_to_int(alpha_bits) = 4.
single_integer_state_to_int(alpha_test_ref) = 5.
single_integer_state_to_int(attrib_stack_depth) = 6.
single_integer_state_to_int(aux_buffers) = 7.
single_integer_state_to_int(blue_bits) = 8.
single_integer_state_to_int(client_attrib_stack_depth) = 9.
single_integer_state_to_int(color_array_size) = 10.
single_integer_state_to_int(color_array_stride) = 11.
single_integer_state_to_int(depth_bits) = 12.
single_integer_state_to_int(depth_clear_value) = 13.
single_integer_state_to_int(edge_flag_array_stride) = 14.
single_integer_state_to_int(feedback_buffer_size) = 15.
single_integer_state_to_int(green_bits) = 16.
single_integer_state_to_int(index_array_stride) = 17.
single_integer_state_to_int(index_bits) = 18.
single_integer_state_to_int(index_offset) = 19.
single_integer_state_to_int(index_shift) = 20.
single_integer_state_to_int(line_stipple_repeat) = 21.
single_integer_state_to_int(list_base) = 22.
single_integer_state_to_int(list_index) = 23.
single_integer_state_to_int(max_attrib_stack_depth) = 24.
single_integer_state_to_int(max_client_attrib_stack_depth) = 25.
single_integer_state_to_int(max_clip_planes) = 26.
single_integer_state_to_int(max_eval_order) = 27.
single_integer_state_to_int(max_lights) = 28.
single_integer_state_to_int(max_list_nesting) = 29.
single_integer_state_to_int(max_modelview_stack_depth) = 30.
single_integer_state_to_int(max_name_stack_depth) = 31.
single_integer_state_to_int(max_pixel_map_table) = 32.
single_integer_state_to_int(max_projection_stack_depth) = 33.
single_integer_state_to_int(max_texture_size) = 34.
single_integer_state_to_int(max_texture_stack_depth) = 35.
single_integer_state_to_int(modelview_stack_depth) = 36.
single_integer_state_to_int(name_stack_depth) = 37.
single_integer_state_to_int(normal_array_stride) = 38.
single_integer_state_to_int(pack_alignment) = 39.
single_integer_state_to_int(pack_row_length) = 40.
single_integer_state_to_int(pack_skip_rows) = 41.
single_integer_state_to_int(projection_stack_depth) = 42.
single_integer_state_to_int(red_bits) = 43.
single_integer_state_to_int(selection_buffer_size) = 44.
single_integer_state_to_int(stencil_bits) = 45.
single_integer_state_to_int(stencil_clear_value) = 46.
single_integer_state_to_int(stencil_ref) = 47.
single_integer_state_to_int(subpixel_bits) = 48.
single_integer_state_to_int(texture_coord_array_size) = 49.
single_integer_state_to_int(texture_coord_array_stride) = 50.
single_integer_state_to_int(texture_stack_depth) = 51.
single_integer_state_to_int(unpack_alignment) = 52.
single_integer_state_to_int(unpack_row_length) = 53.
single_integer_state_to_int(unpack_skip_pixels) = 54.
single_integer_state_to_int(unpack_skip_rows) = 55.
single_integer_state_to_int(vertex_array_size) = 56.
single_integer_state_to_int(vertex_array_stride) = 57.

get_integer(Param, Value, !IO) :-
    get_integer_2(single_integer_state_to_int(Param), Value, !IO).

:- pred get_integer_2(int::in, int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    get_integer_2(Param::in, Value::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLint value;
    
    glGetIntegerv(single_integer_state_flags[Param], &value);
    Value = (MR_Integer) value;
    IO = IO0;
").

:- pragma foreign_enum("C", single_float_state/0, [
    accum_clear_value       - "GL_ACCUM_CLEAR_VALUE",
    alpha_bias              - "GL_ALPHA_BIAS",
    alpha_scale             - "GL_ALPHA_SCALE",
    blue_bias               - "GL_BLUE_BIAS",
    blue_scale              - "GL_BLUE_SCALE",
    current_index           - "GL_CURRENT_INDEX",
    current_raster_distance - "GL_CURRENT_RASTER_DISTANCE",
    current_raster_index    - "GL_CURRENT_RASTER_INDEX",
    depth_bias              - "GL_DEPTH_BIAS",
    depth_scale             - "GL_DEPTH_SCALE",
    fog_density             - "GL_FOG_DENSITY",
    fog_end                 - "GL_FOG_END",
    fog_index               - "GL_FOG_INDEX",
    fog_start               - "GL_FOG_START",
    green_bias              - "GL_GREEN_BIAS",
    green_scale             - "GL_GREEN_SCALE",
    index_clear_value       - "GL_INDEX_CLEAR_VALUE",
    line_stipple_repeat     - "GL_LINE_STIPPLE_REPEAT",
    line_width              - "GL_LINE_WIDTH",
    map1_grid_segments      - "GL_MAP1_GRID_SEGMENTS",
    point_size              - "GL_POINT_SIZE",
    polygon_offset_factor   - "GL_POLYGON_OFFSET_FACTOR",
    polygon_offset_units    - "GL_POLYGON_OFFSET_UNITS",
    red_bias                - "GL_RED_BIAS",
    red_scale               - "GL_RED_SCALE",
    zoom_x                  - "GL_ZOOM_X",
    zoom_y                  - "GL_ZOOM_Y"
]).

:- pragma foreign_proc("C",
    get_float(Param::in, V::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat value;

    glGetFloatv((GLenum) Param, &value);
    V = (MR_Float) value;
    IO = IO0;
").

:- pragma foreign_enum("C", double_integer_state/0, [
    max_viewport_dims - "GL_MAX_VIEWPORT_DIMS"
]).

:- pragma foreign_proc("C",
    get_integer(Param::in, V0::out, V1::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLint values[2];

    glGetIntegerv((GLenum) Param, values);
    V0 = (MR_Integer) values[0];
    V1 = (MR_Integer) values[1];
    IO = IO0;
").

:- pragma foreign_enum("C", double_float_state/0, [
    aliased_point_size_range - "GL_ALIASED_POINT_SIZE_RANGE",
    depth_range              - "GL_DEPTH_RANGE",
    map1_grid_domain         - "GL_MAP1_GRID_DOMAIN",
    map2_grid_segments       - "GL_MAP2_GRID_SEGMENTS"
]).

:- pragma foreign_proc("C", 
    get_float(Param::in, V0::out, V1::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat values[2];

    glGetFloatv((GLenum) Param, values);
    V0 = (MR_Float) values[0];
    V1 = (MR_Float) values[1];
    IO = IO0;
").

:- pragma foreign_enum("C", triple_float_state/0, [
    current_normal - "GL_CURRENT_NORMAL"
]).

:- pragma foreign_proc("C", 
    get_float(Param::in, V0::out, V1::out, V2::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat value[3];
    
    glGetFloatv((GLenum) Param, value);

    V0 = (MR_Float) value[0];
    V1 = (MR_Float) value[1];
    V2 = (MR_Float) value[2];
    IO = IO0;
").

:- pragma foreign_enum("C", quad_float_state/0, [
    color_clear_value           - "GL_COLOR_CLEAR_VALUE",
    current_color               - "GL_CURRENT_COLOR",
    current_raster_color        - "GL_CURRENT_RASTER_COLOR",
    current_raster_position     - "GL_CURRENT_RASTER_POSITION",
    current_texture_coords      - "GL_CURRENT_TEXTURE_COORDS",
    fog_color                   - "GL_FOG_COLOR",
    map2_grid_domain            - "GL_MAP2_GRID_DOMAIN"
]).

:- pragma foreign_proc("C",
    get_float(Param::in, V0::out, V1::out, V2::out, V3::out, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    GLfloat values[4];

    glGetFloatv((GLenum) Param, values);
    V0 = (MR_Float) values[0];
    V1 = (MR_Float) values[1];
    V2 = (MR_Float) values[2];
    V3 = (MR_Float) values[3];
    IO = IO0;
").

%------------------------------------------------------------------------------%

:- pragma foreign_enum("C", string_name/0, [
    vendor     - "GL_VENDOR",
    renderer   - "GL_RENDERER",
    version    - "GL_VERSION",
    extensions - "GL_EXTENSIONS"
]).

:- pragma foreign_proc("C",
    get_string(StrFlag::in, Result::out, IO0::di, IO::uo),
    [may_call_mercury, tabled_for_io, promise_pure, terminates,
        will_not_throw_exception],
"
    const GLubyte *c_str;
    MR_String mer_str;

    c_str = glGetString((GLenum) StrFlag);

    if (c_str == NULL) {
        Result = MOGL_get_string_no();
    } else {
        MR_make_aligned_string_copy(mer_str, c_str);
        Result = MOGL_get_string_yes(mer_str);              
    }       
    
    IO = IO0;
").

:- func get_string_no = maybe(string).
:- pragma foreign_export("C", get_string_no = out, "MOGL_get_string_no").
get_string_no = no.

:- func get_string_yes(string) = maybe(string).
:- pragma foreign_export("C", get_string_yes(in) = out, "MOGL_get_string_yes").
get_string_yes(Str) = yes(Str).

%------------------------------------------------------------------------------%
%
% Server attribute stack
%

:- pragma foreign_decl("C", "
    extern const GLbitfield server_attrib_group_flags[];
").

:- pragma foreign_code("C", "
    const GLbitfield server_attrib_group_flags[] = {
        GL_ACCUM_BUFFER_BIT,
        GL_COLOR_BUFFER_BIT,
        GL_CURRENT_BIT,
        GL_DEPTH_BUFFER_BIT,
        GL_ENABLE_BIT,
        GL_EVAL_BIT,
        GL_FOG_BIT,
        GL_HINT_BIT,
        GL_LIGHTING_BIT,
        GL_LINE_BIT,
        GL_LIST_BIT,
        GL_PIXEL_MODE_BIT,
        GL_POINT_BIT,
        GL_POLYGON_BIT,
        GL_POLYGON_STIPPLE_BIT,
        GL_SCISSOR_BIT,
        GL_STENCIL_BUFFER_BIT,
        GL_TRANSFORM_BIT,
        GL_VIEWPORT_BIT
    };
").

:- func server_attrib_group_to_int(server_attrib_group) = int.

server_attrib_group_to_int(accum_buffer) = 0.
server_attrib_group_to_int(color_buffer) = 1.
server_attrib_group_to_int(current) = 2.
server_attrib_group_to_int(depth_buffer) = 3.
server_attrib_group_to_int(enable) = 4.
server_attrib_group_to_int(eval) = 5.
server_attrib_group_to_int(fog) = 6.
server_attrib_group_to_int(hint) = 7.
server_attrib_group_to_int(lighting) = 8.
server_attrib_group_to_int(line) = 9.
server_attrib_group_to_int(list) = 10.
server_attrib_group_to_int(pixel_mode) = 11.
server_attrib_group_to_int(point) = 12.
server_attrib_group_to_int(polygon) = 13.
server_attrib_group_to_int(polygon_stipple) = 14.
server_attrib_group_to_int(scissor) = 15.
server_attrib_group_to_int(stencil_buffer) = 16.
server_attrib_group_to_int(transform) = 17.
server_attrib_group_to_int(viewport) = 18.

:- pragma foreign_proc("C",
    push_attrib(IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPushAttrib(GL_ALL_ATTRIB_BITS);
    IO = IO0;
").

push_attrib([], _, _) :- error("No server attribute groups specified.").
push_attrib(Groups @ [_ | _], !IO) :-
    Mask = list.foldr((\/), list.map(server_attrib_group_to_bit, Groups), 0),
    push_attrib_2(Mask, !IO).
    
:- func server_attrib_group_to_bit(server_attrib_group) = int.

server_attrib_group_to_bit(Flag) = 
    lookup_server_attrib_group_bit(server_attrib_group_to_int(Flag)).

:- func lookup_server_attrib_group_bit(int) = int.
:- pragma foreign_proc("C",
    lookup_server_attrib_group_bit(Flag::in) = (Mask::out),
    [will_not_call_mercury, promise_pure],
"
    Mask = server_attrib_group_flags[Flag];
").

:- pred push_attrib_2(int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    push_attrib_2(Mask::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPushAttrib((GLbitfield) Mask);
    IO = IO0;
").

:- pragma foreign_proc("C",
    pop_attrib(IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPopAttrib();
    IO = IO0;
").

%------------------------------------------------------------------------------%
%
% Client attribute stack
%

:- pragma foreign_decl("C", "
    extern const GLbitfield client_attrib_group_flags[];
").

:- pragma foreign_code("C", "
    const GLbitfield client_attrib_group_flags[] = {
        GL_CLIENT_VERTEX_ARRAY_BIT,
        GL_CLIENT_PIXEL_STORE_BIT
    };
").

:- func client_attrib_group_to_int(client_attrib_group) = int.

client_attrib_group_to_int(vertex_array) = 0.
client_attrib_group_to_int(pixel_store) = 1.

:- pragma foreign_proc("C",
    push_client_attrib(IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    /*
    ** Some OpenGL implementations don't define 
    ** GL_ALL_CLIENT_ATTRIB_BITS, so we fake its
    ** effect here.
    */
    glPushClientAttrib(GL_CLIENT_VERTEX_ARRAY_BIT);
    glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
    IO = IO0;
").

push_client_attrib([], !IO) :- error("No client attribute groups specified.").
push_client_attrib(Groups @ [_ | _], !IO) :-
    Mask = list.foldr((\/), list.map(client_attrib_group_to_bit, Groups), 0),
    push_client_attrib_2(Mask, !IO).

:- func client_attrib_group_to_bit(client_attrib_group) = int.

client_attrib_group_to_bit(Flag) = 
    lookup_client_attrib_group_bit(client_attrib_group_to_int(Flag)).

:- func lookup_client_attrib_group_bit(int) = int.
:- pragma foreign_proc("C",
    lookup_client_attrib_group_bit(Flag::in) = (Mask::out),
    [will_not_call_mercury, promise_pure, does_not_affect_liveness],
"
    Mask = client_attrib_group_flags[Flag];
"). 

:- pred push_client_attrib_2(int::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    push_client_attrib_2(Mask::in, IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPushClientAttrib((GLbitfield) Mask);
    IO = IO0;
").

:- pragma foreign_proc("C",
    pop_client_attrib(IO0::di, IO::uo),
    [will_not_call_mercury, tabled_for_io, promise_pure,
        does_not_affect_liveness],
"
    glPopClientAttrib();
    IO = IO0;
").

%------------------------------------------------------------------------------%
:- end_module mogl.
%------------------------------------------------------------------------------%
