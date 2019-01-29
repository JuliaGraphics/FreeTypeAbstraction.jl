const Vec = SVector
struct FontExtent{T}
    vertical_bearing::Vec{2, T}
    horizontal_bearing::Vec{2, T}

    advance::Vec{2, T}
    scale::Vec{2, T}
end

import Base: /, *, ==


import Base.Broadcast: BroadcastStyle, AbstractArrayStyle, Broadcasted, DefaultArrayStyle, materialize!, flatten, Style, broadcasted
BroadcastStyle(::Type{<: FontExtent}) = Style{FontExtent}()
BroadcastStyle(::Style{FontExtent}, x) = Style{FontExtent}()
BroadcastStyle(x, ::Style{FontExtent}) = Style{FontExtent}()

function broadcasted(op::Function, f::FontExtent, scaling::StaticVector)
    FontExtent(
        op.(f.vertical_bearing, scaling[1]),
        op.(f.horizontal_bearing, scaling[2]),
        op.(f.advance, scaling),
        op.(f.scale, scaling),
    )
end
function broadcasted(op::Function, ::Type{T}, f::FontExtent) where T
    FontExtent(
        map(x-> op(T, x), f.vertical_bearing),
        map(x-> op(T, x), f.horizontal_bearing),
        map(x-> op(T, x), f.advance),
        map(x-> op(T, x), f.scale),
    )
end

function FontExtent(fontmetric::FreeType.FT_Glyph_Metrics, scale::T = 64.0) where T <: AbstractFloat
    FontExtent(
        Vec{2, T}(fontmetric.vertBearingX, fontmetric.vertBearingY) ./ scale,
        Vec{2, T}(fontmetric.horiBearingX, fontmetric.horiBearingY) ./ scale,
        Vec{2, T}(fontmetric.horiAdvance, fontmetric.vertAdvance) ./ scale,
        Vec{2, T}(fontmetric.width, fontmetric.height) ./ scale
    )
end
function ==(x::FontExtent, y::FontExtent)
    x.vertical_bearing == y.vertical_bearing &&
    x.horizontal_bearing == y.horizontal_bearing &&
    x.advance == y.advance &&
    x.scale == y.scale
end
function FontExtent(fontmetric::FreeType.FT_Glyph_Metrics, scale::Integer)
    FontExtent(
        div.(Vec{2, Int}(fontmetric.vertBearingX, fontmetric.vertBearingY), scale),
        div.(Vec{2, Int}(fontmetric.horiBearingX, fontmetric.horiBearingY), scale),
        div.(Vec{2, Int}(fontmetric.horiAdvance, fontmetric.vertAdvance), scale),
        div.(Vec{2, Int}(fontmetric.width, fontmetric.height), scale)
    )
end

const FREE_FONT_LIBRARY = FT_Library[C_NULL]

function ft_init()
    global FREE_FONT_LIBRARY
    FREE_FONT_LIBRARY[1] != C_NULL && error("Freetype already initalized. init() called two times?")
    err = FT_Init_FreeType(FREE_FONT_LIBRARY)
    return err == 0
end

function ft_done()
    global FREE_FONT_LIBRARY
    FREE_FONT_LIBRARY[1] == C_NULL && error("Library == CNULL. FreeTypeAbstraction.done() called before init(), or done called two times?")
    err = FT_Done_FreeType(FREE_FONT_LIBRARY[1])
    FREE_FONT_LIBRARY[1] = C_NULL
    return err == 0
end

function newface(facename, faceindex::Real = 0, ftlib = FREE_FONT_LIBRARY)
    face = FT_Face[C_NULL]
    err = FT_New_Face(ftlib[1], facename, Int32(faceindex), face)
    if err != 0
        error("Couldn't load font $facename with error $err")
    end
    face
end

mutable struct FTFont
    ft_ptr::FreeType.FT_FaceRec
    function FTFont(ft_ptr::FreeType.FT_FaceRec)
        obj = new(ft_ptr)
        finalizer(FT_Done_Face, obj)
        return obj
    end
end

function FTFont(path::String)
    face = Ref{FT_Face}(C_NULL)
    err = FT_New_Face(ftlib[1], path, Int32(faceindex), face)
    if err != 0
        error("Couldn't load font $facename with error $err")
    end
    return FTFont(face[])
end

setpixelsize(face, x, y) = setpixelsize(face, (x, y))

function setpixelsize(face, size)
    err = FT_Set_Pixel_Sizes(face[1], UInt32(size[1]), UInt32(size[2]))
    if err != 0
    error("Couldn't set the pixel size for font with error $err")
    end
end

function kerning(c1::Char, c2::Char, face::Array{Ptr{FreeType.FT_FaceRec},1}, divisor::Float32)
    i1 = FT_Get_Char_Index(face[], c1)
    i2 = FT_Get_Char_Index(face[], c2)
    kernVec = Vector{FreeType.FT_Vector}(undef, 1)
    err = FT_Get_Kerning(face[], i1, i2, FreeType.FT_KERNING_DEFAULT, pointer(kernVec))
    err != 0 && return zero(Vec{2, Float32})
    return Vec{2, Float32}(kernVec[1].x / divisor, kernVec[1].y / divisor)
end

function loadchar(face, c::Char)
    err = FT_Load_Char(face[1], c, FT_LOAD_RENDER)
    @assert err == 0
end

function renderface(face, c::Char, pixelsize = (32,32))
    setpixelsize(face, pixelsize)
    faceRec = unsafe_load(face[1])
    loadchar(face, c)
    glyphRec    = unsafe_load(faceRec.glyph)
    @assert glyphRec.format == FreeType.FT_GLYPH_FORMAT_BITMAP
    return glyphbitmap(glyphRec.bitmap), FontExtent(glyphRec.metrics)
end

function getextent(face, c::Char, pixelsize)
    setpixelsize(face, pixelsize)
    faceRec = unsafe_load(face[1])
    loadchar(face, c)
    glyphRec = unsafe_load(faceRec.glyph)
    FontExtent(glyphRec.metrics)
end

function glyphbitmap(bmpRec::FreeType.FT_Bitmap)
    @assert bmpRec.pixel_mode == FreeType.FT_PIXEL_MODE_GRAY
    bmp = Matrix{UInt8}(undef, bmpRec.width, bmpRec.rows)
    row = bmpRec.buffer
    if bmpRec.pitch < 0
        row -= bmpRec.pitch * (rbmpRec.rows - 1)
    end

    for r = 1:bmpRec.rows
        srcArray = unsafe_wrap(Array, row, bmpRec.width)
        bmp[:, r] = srcArray
        row += bmpRec.pitch
    end
    return bmp
end

one_or_typemax(::Type{T}) where {T<:Union{Real,Colorant}} = T<:Integer ? typemax(T) : oneunit(T)

"""
    renderstring!(img::AbstractMatrix, str::String, face, pixelsize, y0, x0;
    fcolor=one_or_typemax(T), bcolor=zero(T), halign=:hleft, valign=:vbaseline) -> Matrix

Render `str` into `img` using the font `face` of size `pixelsize` at coordinates `y0,x0`.

# Arguments
* `y0,x0`: origin is in upper left with positive `y` going down
* `fcolor`: foreground color; typemax(T) for T<:Integer, otherwise one(T)
* `bcolor`: background color; set to `nothing` for transparent
* `halign`: :hleft, :hcenter, or :hright
* `valign`: :vtop, :vcenter, :vbaseline, or :vbottom
"""
function renderstring!(
        img::AbstractMatrix{T}, str::String, face, pixelsize, y0, x0;
        fcolor::T = one_or_typemax(T), bcolor::Union{T,Nothing} = zero(T),
        halign::Symbol = :hleft, valign::Symbol = :vbaseline
    ) where T<:Union{Real,Colorant}
    bitmaps = Vector{Matrix{UInt8}}(undef, lastindex(str))
    metrics = Vector{FontExtent{Int}}(undef, lastindex(str))
    ymin = ymax = sumadvancex = 0
    for (istr, char) = enumerate(str)
        bitmap, metric_float = renderface(face, char, pixelsize)
        metric = round.(Int, metric_float)
        bitmaps[istr] = bitmap
        metrics[istr] = metric
        w, h = metric.scale
        bx, by = metric.horizontal_bearing
        ymin = min(ymin, by - h)
        ymax = max(ymax, by)
        sumadvancex += metric.advance[1]
    end

    px = x0 - (halign == :hright ? sumadvancex : halign == :hcenter ? sumadvancex >> 1 : 0)
    py = y0 + (
        valign == :vtop ? ymax : valign == :vbottom ? ymin :
        valign == :vcenter ? (ymax - ymin) >> 1 + ymin : 0
    )
    bitmapmax = typemax(eltype(bitmaps[1]))

    imgh, imgw = size(img)
    if bcolor != nothing
        img[
            clamp(py-ymax+1, 1, imgh) : clamp(py-ymin-1, 1, imgh),
            clamp(px-1, 1, imgw) : clamp(px+sumadvancex-1, 1, imgw)
        ] .= bcolor
    end

    local prev_char::Char
    for (istr, char) = enumerate(str)
        w, h = metrics[istr].scale
        bx, by = metrics[istr].horizontal_bearing
        if istr == 1
            prev_char = char
        else
            kx, ky = map(x-> round(Int, x), kerning(prev_char, char, face, 64.0f0))
            px += kx
        end
        cliprowlo, cliprowhi = max(0, by-py), max(0, h+py-by-imgh)
        clipcollo, clipcolhi = max(0, bx-px), max(0, w+px-bx-imgw)
        if bcolor == nothing
            for row = 1+cliprowlo : h-cliprowhi, col = 1+clipcollo : w-clipcolhi
                bitmaps[istr][col,row]==0 && continue
                c1 = bitmaps[istr][col,row] / bitmapmax * fcolor
                img[row+py-by, col+px-bx] = T <: Integer ? round(T, c1) : T(c1)
            end
        else
            for row = 1+cliprowlo : h-cliprowhi, col = 1+clipcollo : w-clipcolhi
                bitmaps[istr][col, row] == 0 && continue
                w1 = bitmaps[istr][col, row] / bitmapmax
                c1 = w1 * fcolor
                c0 = (1.0 - w1) * bcolor
                img[row + py - by, col + px - bx] = T <: Integer ? round(T, c1 + c0) : T(c1 + c0)
            end
        end
        px += metrics[istr].advance[1]
    end
    img
end
