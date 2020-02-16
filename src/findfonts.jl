mutable struct FTFont
    ft_ptr::FreeType.FT_FaceRec
    pixel_size::Int
    use_cache::Bool
    cache::Dict{Char, FontExtent{Float32}}
    function FTFont(ft_ptr::FreeType.FT_FaceRec, pixel_size::Int=64, use_cache::Bool=true)
        cache = Dict{Char, FontExtent{Float32}}()
        face = new(ft_ptr, pixel_size, use_cache, cache)
        finalizer(FT_Done_Face, face)
        FT_Set_Pixel_Sizes(face, pixel_size, 0);
        return face
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

function FTFont(font_ptr::Ptr{FreeType.FT_FaceRec})
    face_rect = unsafe_load(font_ptr)
    return FTFont(face_rect)
end

# C interop
function Base.cconvert(::Type{FreeType.FT_Face}, font::FTFont)
    return font
end

function Base.unsafe_convert(::Type{FreeType.FT_Face}, font::FTFont)
    ptr = Base.pointer_from_objref(font)
    return convert(FreeType.FT_Face, ptr)
end

function Base.propertynames(font::FTFont)
    return fieldnames(FreeType.FT_FaceRec)
end

function Base.getproperty(font::FTFont, fieldname::Symbol)
    fontrect = getfield(font, :ft_ptr)
    field = getfield(fontrect, fieldname)
    if field isa Ptr{FT_String}
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

function check_error(err, error_msg)
    if err != 0
        error(error_msg * " with error: $(err)")
    end
end

use_cache(face::FTFont) = getfield(face, :use_cache)
get_cache(face::FTFont) = getfield(face, :cache)

if Sys.isapple()
    function _font_paths()
        [
            "/Library/Fonts", # Additional fonts that can be used by all users. This is generally where fonts go if they are to be used by other applications.
            joinpath(homedir(), "Library/Fonts"), # Fonts specific to each user.
            "/Network/Library/Fonts", # Fonts shared for users on a network
        ]
    end
elseif Sys.iswindows()
    _font_paths() = [joinpath(get(ENV, "SYSTEMROOT", "C:\\Windows"), "Fonts")]
else
    function add_recursive(result, path)
        for p in readdir(path)
            pabs = joinpath(path, p)
            if isdir(pabs)
                push!(result, pabs)
                add_recursive(result, pabs)
            end
        end
    end
    function _font_paths()
        result = String[]
        for p in ("/usr/share/fonts", joinpath(homedir(), "/.fonts"), "/usr/local/share/fonts",)
            if isdir(p)
                add_recursive(result, p)
            end
        end
        result
    end
end


freetype_extensions() = (".FON", ".OTC", ".FNT", ".BDF", ".PFR", ".OTF", ".TTF", ".TTC", ".CFF", ".WOFF")

function freetype_can_read(font::String)
    fontname, ext = splitext(font)
    uppercase(ext) in freetype_extensions()
end

function loaded_faces()
    if isempty(loaded_fonts)
        for path in fontpaths()
            for font in readdir(path)
                # There doesn't really seem to be a reliable pattern here.
                # there are fonts that should be supported and dont load
                # and fonts with an extension not on the FreeType website, which
                # load just fine. So we just try catch it!
                #freetype_can_read(font) || continue
                fpath = joinpath(path, font)
                try
                    push!(loaded_fonts, newface(fpath)[1])
                catch
                end
            end
        end
    end
    return loaded_fonts
end

family_name(x::String) = replace(lowercase(x), ' ' => "") # normalize

function family_name(x)
    fname = x.family_name
    fname == C_NULL && return ""
    family_name(unsafe_string(fname))
end

function style_name(x)
    sname = x.style_name
    sname == C_NULL && return ""
    lowercase(unsafe_string(sname))
end

function match_font(face, name, italic, bold)
    ft_rect = unsafe_load(face)
    fname = family_name(ft_rect)
    sname = style_name(ft_rect)
    italic = italic == (sname == "italic")
    bold = bold == (sname == "bold")
    perfect_match = (fname == name) && italic && bold
    fuzzy_match = occursin(name, fname)
    score = fuzzy_match + bold + italic
    return perfect_match, fuzzy_match, score
end

function try_load(fpath)
    try
        newface(fpath)[]
    catch e
        return nothing
    end
end

function findfont(
        name::String;
        italic = false, bold = false, additional_fonts::String = ""
    )
    font_folders = copy(fontpaths())
    normalized_name = family_name(name)
    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)
    candidates = Pair{Ptr{FreeType.FT_FaceRec}, Int}[]
    for folder in font_folders
        for font in readdir(folder)
            fpath = joinpath(folder, font)
            face = try_load(fpath)
            face === nothing && continue
            perfect_match, fuzzy_match, score = match_font(
                face, normalized_name, italic, bold
            )
            perfect_match && return face
            if fuzzy_match
                push!(candidates, face => score)
            else
                FT_Done_Face(face)
            end
        end
    end
    if !isempty(candidates)
        sort!(candidates, by = last)
        final_candidate = pop!(candidates)
        foreach(x-> FT_Done_Face(x[1]), candidates)
        return FTFont(final_candidate[1])
    end
    return nothing
end
