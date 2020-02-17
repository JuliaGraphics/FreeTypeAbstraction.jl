
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
        img::AbstractMatrix{T}, str::String, face::FTFont, pixelsize, y0, x0;
        fcolor::T = one_or_typemax(T), bcolor::Union{T,Nothing} = zero(T),
        halign::Symbol = :hleft, valign::Symbol = :vbaseline
    ) where T<:Union{Real,Colorant}
    setpixelsize(face, pixelsize)
    bitmaps = Vector{Matrix{UInt8}}(undef, lastindex(str))
    metrics = Vector{FontExtent{Int}}(undef, lastindex(str))
    ymin = ymax = sumadvancex = 0

    for (istr, char) = enumerate(str)
        bitmap = renderface(face, char)
        metric_float = get_extent(face, char)
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
    return img
end
