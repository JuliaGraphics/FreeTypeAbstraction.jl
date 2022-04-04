check_error(err, error_msg) = err == 0 || error(error_msg * " with error: $(err)")

const FREE_FONT_LIBRARY = FT_Library[C_NULL]

function ft_init()
    FREE_FONT_LIBRARY[1] != C_NULL && error("Freetype already initalized. init() called two times?")
    err = FT_Init_FreeType(FREE_FONT_LIBRARY)
    return err == 0
end

function ft_done()
    FREE_FONT_LIBRARY[1] == C_NULL && error("Library == CNULL. FreeTypeAbstraction.done() called before init(), or done called two times?")
    err = FT_Done_FreeType(FREE_FONT_LIBRARY[1])
    FREE_FONT_LIBRARY[1] = C_NULL
    return err == 0
end

function newface(facename, faceindex::Real=0, ftlib=FREE_FONT_LIBRARY)
    face = Ref{FT_Face}()
    err = FT_New_Face(ftlib[1], facename, Int32(faceindex), face)
    check_error(err, "Couldn't load font $facename")
    return face[]
end


struct FontExtent{T}
    vertical_bearing::Vec{2, T}
    horizontal_bearing::Vec{2, T}

    advance::Vec{2, T}
    scale::Vec{2, T}
end

hadvance(ext::FontExtent) = ext.advance[1]
vadvance(ext::FontExtent) = ext.advance[2]
inkwidth(ext::FontExtent) = ext.scale[1]
inkheight(ext::FontExtent) = ext.scale[2]
hbearing_ori_to_left(ext::FontExtent) = ext.horizontal_bearing[1]
hbearing_ori_to_top(ext::FontExtent) = ext.horizontal_bearing[2]
leftinkbound(ext::FontExtent) = hbearing_ori_to_left(ext)
rightinkbound(ext::FontExtent) = leftinkbound(ext) + inkwidth(ext)
bottominkbound(ext::FontExtent) = hbearing_ori_to_top(ext) - inkheight(ext)
topinkbound(ext::FontExtent) = hbearing_ori_to_top(ext)

BroadcastStyle(::Type{<: FontExtent}) = Style{FontExtent}()
BroadcastStyle(::Style{FontExtent}, x) = Style{FontExtent}()
BroadcastStyle(x, ::Style{FontExtent}) = Style{FontExtent}()

function broadcasted(op::Function, f::FontExtent, scaling::StaticVector)
    return FontExtent(
        op.(f.vertical_bearing, scaling[1]),
        op.(f.horizontal_bearing, scaling[2]),
        op.(f.advance, scaling),
        op.(f.scale, scaling),
    )
end

function broadcasted(op::Function, f::FontExtent)
    return FontExtent(
        op.(f.vertical_bearing),
        op.(f.horizontal_bearing),
        op.(f.advance),
        op.(f.scale),
    )
end

function broadcasted(op::Function, ::Type{T}, f::FontExtent) where T
    return FontExtent(
        map(x-> op(T, x), f.vertical_bearing),
        map(x-> op(T, x), f.horizontal_bearing),
        map(x-> op(T, x), f.advance),
        map(x-> op(T, x), f.scale),
    )
end

function FontExtent(fontmetric::FreeType.FT_Glyph_Metrics, scale::T = 64.0) where T <: AbstractFloat
    return FontExtent(
        Vec{2, T}(fontmetric.vertBearingX, fontmetric.vertBearingY) ./ scale,
        Vec{2, T}(fontmetric.horiBearingX, fontmetric.horiBearingY) ./ scale,
        Vec{2, T}(fontmetric.horiAdvance, fontmetric.vertAdvance) ./ scale,
        Vec{2, T}(fontmetric.width, fontmetric.height) ./ scale
    )
end

function ==(x::FontExtent, y::FontExtent)
    return (
        x.vertical_bearing == y.vertical_bearing &&
        x.horizontal_bearing == y.horizontal_bearing &&
        x.advance == y.advance &&
        x.scale == y.scale
    )
end

function FontExtent(fontmetric::FreeType.FT_Glyph_Metrics, scale::Integer)
    return FontExtent(
        div.(Vec{2, Int}(fontmetric.vertBearingX, fontmetric.vertBearingY), scale),
        div.(Vec{2, Int}(fontmetric.horiBearingX, fontmetric.horiBearingY), scale),
        div.(Vec{2, Int}(fontmetric.horiAdvance, fontmetric.vertAdvance), scale),
        div.(Vec{2, Int}(fontmetric.width, fontmetric.height), scale)
    )
end

function bearing(extent::FontExtent{T}) where T
    return Vec2{T}(
        +extent.horizontal_bearing[1],
        -extent.horizontal_bearing[2],
    )
end

function safe_free(face)
    ptr = getfield(face, :ft_ptr)
    if ptr != C_NULL && FREE_FONT_LIBRARY[1] != C_NULL
        FT_Done_Face(face)
    end
end

boundingbox(extent::FontExtent{T}) where T = Rect2(bearing(extent), Vec2{T}(extent.scale))

mutable struct FTFont
    ft_ptr::FreeType.FT_Face
    use_cache::Bool
    extent_cache::Dict{Char, FontExtent{Float32}}
    function FTFont(ft_ptr::FreeType.FT_Face, use_cache::Bool=true)
        extent_cache = Dict{Tuple{Int, Char}, FontExtent{Float32}}()
        face = new(ft_ptr, use_cache, extent_cache)
        finalizer(safe_free, face)
        return face
    end
end

use_cache(face::FTFont) = getfield(face, :use_cache)
get_cache(face::FTFont) = getfield(face, :extent_cache)

FTFont(path::String) = FTFont(newface(path))

# C interop
Base.cconvert(::Type{FreeType.FT_Face}, font::FTFont) = font

Base.unsafe_convert(::Type{FreeType.FT_Face}, font::FTFont) = getfield(font, :ft_ptr)

Base.propertynames(font::FTFont) = fieldnames(FreeType.FT_FaceRec)

function Base.getproperty(font::FTFont, fieldname::Symbol)
    fontrect = unsafe_load(getfield(font, :ft_ptr))
    field = getfield(fontrect, fieldname)
    if field isa Ptr{FT_String}
        field == C_NULL && return ""
        return unsafe_string(field)
    else
        return field
    end
end

function Base.show(io::IO, font::FTFont)
    print(io, "FTFont (family = $(font.family_name), style = $(font.style_name))")
end

# Allow broadcasting over fonts
Base.Broadcast.broadcastable(ft::FTFont) = Ref(ft)

function set_pixelsize(face::FTFont, size::Integer)
    err = FT_Set_Pixel_Sizes(face, size, size)
    check_error(err, "Couldn't set pixelsize")
    return size
end

function kerning(c1::Char, c2::Char, face::FTFont)
    i1 = FT_Get_Char_Index(face, c1)
    i2 = FT_Get_Char_Index(face, c2)
    kerning2d = Ref{FreeType.FT_Vector}()
    err = FT_Get_Kerning(face, i1, i2, FreeType.FT_KERNING_DEFAULT, kerning2d)
    # Can error if font has no kerning! Since that's somewhat expected, we just return 0
    err != 0 && return Vec2f(0)
    # 64 since metrics are in 1/64 units (units to 26.6 fractional pixels)
    divisor = 64
    return Vec2f(kerning2d[].x / divisor, kerning2d[].y / divisor)
end

function get_extent(face::FTFont, char::Char)
    if use_cache(face)
        get!(get_cache(face), char) do
            return internal_get_extent(face, char)
        end
    else
        return internal_get_extent(face, char)
    end
end

function internal_get_extent(face::FTFont, char::Char)
    #=
    Load chars without scaling. This leaves all glyph metrics that can be
    retrieved in font units, which can be normalized by dividing with the
    font's units_per_EM. This is more robust than relying on extents
    that are only valid with a specific pixelsize, because a font's
    pixelsize can be silently changed by third parties, such as Cairo.
    If that happens, all glyph metrics are incorrect. We avoid this by using the normalized space.
    =#
    err = FT_Load_Char(face, char, FT_LOAD_NO_SCALE)
    check_error(err, "Could not load char to get extent.")
    # This gives us the font metrics in normalized units (0, 1), with negative
    # numbers interpreted as an offset
    return FontExtent(unsafe_load(face.glyph).metrics, Float32(face.units_per_EM))
end

descender(font) = font.descender / font.units_per_EM
ascender(font) = font.ascender / font.units_per_EM
