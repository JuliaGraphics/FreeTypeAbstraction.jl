function check_error(err, error_msg)
    if err != 0
        error(error_msg * " with error: $(err)")
    end
end

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
    return (x.vertical_bearing == y.vertical_bearing &&
            x.horizontal_bearing == y.horizontal_bearing &&
            x.advance == y.advance &&
            x.scale == y.scale)
end

function FontExtent(fontmetric::FreeType.FT_Glyph_Metrics, scale::Integer)
    return FontExtent(
        div.(Vec{2, Int}(fontmetric.vertBearingX, fontmetric.vertBearingY), scale),
        div.(Vec{2, Int}(fontmetric.horiBearingX, fontmetric.horiBearingY), scale),
        div.(Vec{2, Int}(fontmetric.horiAdvance, fontmetric.vertAdvance), scale),
        div.(Vec{2, Int}(fontmetric.width, fontmetric.height), scale)
    )
end

function safe_free(face)
    ptr = getfield(face, :ft_ptr)
    if ptr != C_NULL && FREE_FONT_LIBRARY[1] != C_NULL
        FT_Done_Face(face)
    end
end

mutable struct FTFont
    ft_ptr::FreeType.FT_Face
    pixel_size::Int
    use_cache::Bool
    cache::Dict{Char, FontExtent{Float32}}
    function FTFont(ft_ptr::FreeType.FT_Face, pixel_size::Int=64, use_cache::Bool=true)
        cache = Dict{Char, FontExtent{Float32}}()
        face = new(ft_ptr, pixel_size, use_cache, cache)
        finalizer(safe_free, face)
        FT_Set_Pixel_Sizes(face, pixel_size, 0);
        return face
    end
end

use_cache(face::FTFont) = getfield(face, :use_cache)
get_cache(face::FTFont) = getfield(face, :cache)

function FTFont(path::String)
    return FTFont(newface(path))
end

# C interop
function Base.cconvert(::Type{FreeType.FT_Face}, font::FTFont)
    return font
end

function Base.unsafe_convert(::Type{FreeType.FT_Face}, font::FTFont)
    return getfield(font, :ft_ptr)
end

function Base.propertynames(font::FTFont)
    return fieldnames(FreeType.FT_FaceRec)
end

function Base.getproperty(font::FTFont, fieldname::Symbol)
    fontrect = unsafe_load(getfield(font, :ft_ptr))
    field = getfield(fontrect, fieldname)
    if field isa Ptr{FT_String}
        field == C_NULL && return ""
        return unsafe_string(field)
    # Some fields segfault with unsafe_load...Lets find out which another day :D
    elseif field isa Ptr{FreeType.LibFreeType.FT_GlyphSlotRec}
        return unsafe_load(field)
    else
        return field
    end
end

get_pixelsizes(face::FTFont) = (get_pixelsize(face), get_pixelsize(face))
get_pixelsize(face::FTFont) = getfield(face, :pixel_size)
reset_pixelsize(face::FTFont) = FT_Set_Pixel_Sizes(face, get_pixelsize(face), 0)
setpixelsize(face::FTFont, x, y) = setpixelsize(face, (x, y))

function setpixelsize(face::FTFont, size::NTuple{2, <:Integer})
    err = FT_Set_Pixel_Sizes(face, UInt32(size[1]), UInt32(size[2]))
    check_error(err, "Couldn't set pixelsize")
end

function kerning(c1::Char, c2::Char, face::FTFont, divisor::Float32)
    i1 = FT_Get_Char_Index(face, c1)
    i2 = FT_Get_Char_Index(face, c2)
    kerning2d = Ref{FreeType.FT_Vector}()
    err = FT_Get_Kerning(face, i1, i2, FreeType.FT_KERNING_DEFAULT, kerning2d)
    # Can error if font has no kerning! Since that's somewhat expected, we just return 0
    err != 0 && return Vec2f0(0)
    return Vec2f0(kerning2d[].x / divisor, kerning2d[].y / divisor)
end

function loadchar(face::FTFont, c::Char)
    err = FT_Load_Char(face, c, FT_LOAD_RENDER)
    check_error(err, "Could not load char to render.")
end

function renderface(face::FTFont, c::Char)
    loadchar(face, c)
    glyph = face.glyph
    @assert glyph.format == FreeType.FT_GLYPH_FORMAT_BITMAP
    return glyphbitmap(glyph.bitmap)
end

function glyphbitmap(bitmap::FreeType.FT_Bitmap)
    @assert bitmap.pixel_mode == FreeType.FT_PIXEL_MODE_GRAY
    bmp = Matrix{UInt8}(undef, bitmap.width, bitmap.rows)
    row = bitmap.buffer
    if bitmap.pitch < 0
        row -= bitmap.pitch * (rbmpRec.rows - 1)
    end
    for r in 1:bitmap.rows
        src = unsafe_wrap(Array, row, bitmap.width)
        bmp[:, r] = src
        row += bitmap.pitch
    end
    return bmp
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
    err = FT_Load_Char(face, char, FT_LOAD_DEFAULT)
    check_error(err, "Could not load char to get extend.")
    metrics = face.glyph.metrics
    return FontExtent(metrics, Float32(get_pixelsize(face)))
end

function bearing(extent)
    return Vec2f0(extent.horizontal_bearing[1],
                  -(extent.scale[2] - extent.horizontal_bearing[2]))
end
