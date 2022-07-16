iter_or_array(x) = repeated(x)
iter_or_array(x::Repeated) = x
iter_or_array(x::AbstractArray) = x
# We treat staticarrays as scalar
iter_or_array(x::Union{Mat, StaticVector}) = repeated(x)


function metrics_bb(glyph, font::FTFont, pixel_size)
    extent = get_extent(font, glyph) .* Vec2f(pixel_size)
    return boundingbox(extent), extent
end

function boundingbox(glyph, font::FTFont, pixel_size)
    bb, extent = metrics_bb(glyph, font, pixel_size)
    return bb
end

function glyph_ink_size(glyph, font::FTFont, pixel_size)
    bb, extent = metrics_bb(glyph, font, pixel_size)
    return widths(bb)
end

function inkboundingbox(ext::FontExtent)
    l = leftinkbound(ext)
    r = rightinkbound(ext)
    b = bottominkbound(ext)
    t = topinkbound(ext)
    return Rect2f((l, b), (r - l, t - b))
end

function height_insensitive_boundingbox(ext::FontExtent, font::FTFont)
    l = leftinkbound(ext)
    r = rightinkbound(ext)
    b = descender(font)
    t = ascender(font)
    return Rect2f((l, b), (r - l, t - b))
end
