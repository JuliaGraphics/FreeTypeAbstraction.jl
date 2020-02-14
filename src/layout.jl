
iter_or_array(x) = repeated(x)
iter_or_array(x::Repeated) = x
iter_or_array(x::Array) = x
iter_or_array(x::Vector{Ptr{FreeType.FT_FaceRec}}) = repeated(x)


# TODO, this function takes way too long... Will need caching or so
function get_extent(face::Vector{Ptr{FreeType.FT_FaceRec}}, char::Char)
    face_rec = unsafe_load(face[1])
    err = FT_Load_Char(face[1], char, FT_LOAD_DEFAULT)
    @assert err == 0
    glyph_rec = unsafe_load(face_rec.glyph);
    metrics = glyph_rec.metrics
    return FontExtent(metrics, 64.0)
end

function bearing(extent)
    return Vec2f0(extent.horizontal_bearing[1],
                  -(extent.scale[2] - extent.horizontal_bearing[2]))
end

"""
    iterate_extents(f, line::AbstractString, fonts, scales)
Iterates over the extends of the characters (glyphs) in line!
Newlines will be drawn like any other character.
`fonts` can be a vector of fonts, or a single font.
`scales` can be a single float or a Vec2, or a vector of any of those.

`f` will get called with `(char::Char, glyph_box::Rec2D, glyph_advance::Point2f0)`.

`char` is the currently iterated char.

`glyph_box` is the boundingbox of the glyph.
widths(box) will be the size of the bitmap, while minimum(box) is where one starts drawing the glyph.
For the minimum at y position, 0 is the where e.g. `m` starts, so `g` will start in the negative, while `^` will start positive.

`glyph_advance` The amount one advances after glyph, before drawing next glyph.
"""
function iterate_extents(f, line::AbstractString, fonts, scales)
    iterator = zip(line, iter_or_array(scales), iter_or_array(fonts))
    lastpos = 0.0
    for (char, scale, font) in iterator
        extent = get_extent(font, char)
        mini = bearing(extent) .+ Vec2f0(lastpos, 0.0)
        glyph_box = Rect2D(mini, Vec2f0(extent.scale))
        glyph_advance = Point2f0(extent.advance)
        lastpos += glyph_advance[1]
        f(char, glyph_box, glyph_advance)
    end
end

const Rect2D = HyperRectangle{2, Float32}

function glyph_rects(line::AbstractString, fonts, scales)
    rects = Rect2D[]
    iterate_extents(line, fonts, scales) do char, box, advance
        push!(rects, box)
    end
    return rects
end

function boundingbox(line::AbstractString, fonts, scales)
    reduce(union, glyph_rects(lines, fonts, scales))
end
