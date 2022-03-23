
function loadchar(face::FTFont, c::Char)
    err = FT_Load_Char(face, c, FT_LOAD_RENDER)
    check_error(err, "Could not load char to render.")
end

function renderface(face::FTFont, c::Char, pixelsize::Integer)
    set_pixelsize(face, pixelsize)
    loadchar(face, c)
    glyph = unsafe_load(face.glyph)
    @assert glyph.format == FreeType.FT_GLYPH_FORMAT_BITMAP
    return glyphbitmap(glyph.bitmap), FontExtent(glyph.metrics)
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

one_or_typemax(::Type{T}) where {T<:Union{Real,Colorant}} = T<:Integer ? typemax(T) : oneunit(T)

"""
    renderstring!(img::AbstractMatrix, str::String, face, pixelsize, y0, x0;
    fcolor=one_or_typemax(T), bcolor=zero(T), halign=:hleft, valign=:vbaseline) -> Matrix

Render `str` into `img` using the font `face` of size `pixelsize` at coordinates `y0,x0`.

# Arguments
* `y0,x0`: origin is in upper left with positive `y` going down
* `fcolor`: foreground color; AbstractVector{T}, typemax(T) for T<:Integer, otherwise one(T)
* `gcolor`: background color; AbstractVector{T}, typemax(T) for T<:Integer, otherwise one(T)
* `bcolor`: canvas background color; set to `nothing` for transparent
* `halign`: :hleft, :hcenter, or :hright
* `valign`: :vtop, :vcenter, :vbaseline, or :vbottom
"""
function renderstring!(
        img::AbstractMatrix{T}, str::Union{AbstractVector{Char},String}, face::FTFont, pixelsize::Union{Int, Tuple{Int, Int}}, y0, x0;
        fcolor::Union{AbstractVector{T},T} = one_or_typemax(T),
        gcolor::Union{AbstractVector{T},T,Nothing} = nothing,
        bcolor::Union{T,Nothing} = zero(T),
        halign::Symbol = :hleft, valign::Symbol = :vbaseline
    ) where T<:Union{Real,Colorant}

    if pixelsize isa Tuple
        @warn "using tuple for pixelsize is deprecated, please use one integer"
        pixelsize = pixelsize[1]
    end

    str = str isa AbstractVector ? String(str) : str

    set_pixelsize(face, pixelsize)

    bitmaps = Vector{Matrix{UInt8}}(undef, lastindex(str))
    metrics = Vector{FontExtent{Int}}(undef, lastindex(str))
    # ymin and ymax w.r.t the baseline
    ymin = ymax = sumadvancex = 0

    for (istr, char) = enumerate(str)
        bitmap, metric_float = renderface(face, char, pixelsize)
        metric = round.(Int, metric_float)
        bitmaps[istr] = bitmap
        metrics[istr] = metric

        # scale of glyph (size of bitmap)
        w, h = metric.scale
        # offset between glyph origin and bitmap top left corner
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
    if bcolor !== nothing
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
            kx, ky = map(x-> round(Int, x), kerning(prev_char, char, face))
            px += kx
        end

        fcol = fcolor isa AbstractVector ? fcolor[istr] : fcolor
        gcol = gcolor isa AbstractVector ? gcolor[istr] : gcolor

        # trim parts of glyph images that are outside the destination
        cliprowlo, cliprowhi = max(0, -(py-by)), max(0, py - by + h - imgh)
        clipcollo, clipcolhi = max(0, -bx-px),   max(0, px + bx + w - imgw)

        if gcol === nothing
            for row = 1+cliprowlo : h-cliprowhi, col = 1+clipcollo : w-clipcolhi
                bitmaps[istr][col,row] == 0 && continue
                c1 = bitmaps[istr][col,row] / bitmapmax * fcol
                img[row+py-by, col+px+bx] = T <: Integer ? round(T, c1) : T(c1)
            end
        else
            img[
                clamp(py-ymax+1, 1, imgh) : clamp(py-ymin-1, 1, imgh),
                clamp(px-1, 1, imgw) : clamp(px+sumadvancex-1, 1, imgw)
            ] .= gcol
            for row = 1+cliprowlo : h-cliprowhi, col = 1+clipcollo : w-clipcolhi
                bitmaps[istr][col, row] == 0 && continue
                w1 = bitmaps[istr][col, row] / bitmapmax
                c1 = w1 * fcol
                c0 = (1.0 - w1) * gcol
                img[row + py - by, col + px + bx] = T <: Integer ? round(T, c1 + c0) : T(c1 + c0)
            end
        end
        px += metrics[istr].advance[1]
    end
    return img
end
