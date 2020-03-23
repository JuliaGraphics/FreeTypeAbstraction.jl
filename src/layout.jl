const Rect2D = HyperRectangle{2, Float32}

iter_or_array(x) = repeated(x)
iter_or_array(x::Repeated) = x
iter_or_array(x::AbstractArray) = x
# We treat staticarrays as scalar
iter_or_array(x::StaticArray) = repeated(x)


function metrics_bb(char::Char, font::FTFont, scale)
    extent = get_extent(font, char) .* Vec2f0(scale)
    mini = bearing(extent)
    return Rect2D(mini, Vec2f0(extent.scale)), extent
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
        glyph_box, extent = metrics_bb(char, font, scale)
        mini = minimum(glyph_box) .+ Vec2f0(lastpos, 0.0)
        glyph_box = Rect2D(mini, widths(glyph_box))
        glyph_advance = Point2f0(extent.advance)
        lastpos += glyph_advance[1]
        f(char, glyph_box, glyph_advance)
    end
end


function glyph_rects(line::AbstractString, fonts, scales)
    rects = Rect2D[]
    iterate_extents(line, fonts, scales) do char, box, advance
        push!(rects, box)
    end
    return rects
end

function boundingbox(line::AbstractString, fonts, scales)
    return reduce(union, glyph_rects(line, fonts, scales))
end
