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

family_name(x::String) = replace(lowercase(x), ' ' => "") # normalize

function family_name(x::FTFont)
    family_name(x.family_name)
end

function style_name(x::FTFont)
    lowercase(x.style_name)
end

function match_font(face::FTFont, name, italic, bold)
    fname = family_name(face)
    sname = style_name(face)
    italic = italic == (sname == "italic")
    bold = bold == (sname == "bold")
    perfect_match = (fname == name) && italic && bold
    fuzzy_match = occursin(name, fname)
    score = fuzzy_match + bold + italic
    return perfect_match, fuzzy_match, score
end

function try_load(fpath)
    try
        return FTFont(fpath)
    catch e
        return nothing
    end
end

function findfont(
        name::String;
        italic::Bool=false, bold::Bool=false, additional_fonts::String=""
    )
    font_folders = copy(fontpaths())
    normalized_name = family_name(name)
    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)
    candidates = Pair{FTFont, Int}[]
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
            end
        end
    end
    if !isempty(candidates)
        sort!(candidates; by=last)
        final_candidate = pop!(candidates)
        return final_candidate[1]
    end
    return nothing
end
