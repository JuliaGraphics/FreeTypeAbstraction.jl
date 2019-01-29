
if Sys.isapple()
    function _font_paths()
        [
            "/Library/Fonts", # Additional fonts that can be used by all users. This is generally where fonts go if they are to be used by other applications.
            "~/Library/Fonts", # Fonts specific to each user.
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
        foreach(FT_Done_Face, candidates)
        return final_candidate
    end
    return nothing
end
