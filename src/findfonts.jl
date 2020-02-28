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

"""
Match a font using the user-specified search string, by increasing the score
for each part that appears in the font family + style name, and decreasing it
for each part that doesn't. The function also prefers shorter font names when
encountering similar scores.


Example:

If we had only four fonts:
- Helvetica
- Helvetica Neue
- Helvetica Neue Light
- Times New Roman

Then this is how this function would match different search strings:
- "helvetica"           => Helvetica
- "helv"                => Helvetica
- "HeLvEtIcA"           => Helvetica
- "helvetica neue"      => Helvetica Neue
- "tica eue"            => Helvetica Neue
- "helvetica light"     => Helvetica Neue Light
- "light"               => Helvetica Neue Light
- "helvetica bold"      => Helvetica
- "helvetica neue bold" => Helvetica Neue
- "times"               => Times New Roman
- "times new roman"     => Times New Roman
- "arial"               => no match
"""
function match_font(face::FTFont, searchstring)
    fname = family_name(face)
    sname = style_name(face)
    full_name = "$fname $sname"
    # \W splits at all groups of non-word characters (like space, -, ., etc)
    searchparts = unique(split(lowercase(searchstring), r"\W+", keepempty=false))
    # count letters of parts that occurred in the font name positively and those that didn't negatively.
    # we assume that the user knows at least parts of the name and doesn't misspell them
    # but they might not know the exact name, especially for long font names, or they
    # might simply not want to be forced to spell it out completely.
    # therefore we let each part we can find count towards a font, and each that
    # doesn't match against it, therefore rejecting fonts that mismatch more parts
    # than they match. this heuristic should be good enough to provide a hassle-free
    # font selection experience where most spellings that are expected to work, work.
    match_score = sum(map(part -> sign(occursin(part, full_name)) * length(part), searchparts))
    # give shorter font names that matched equally well a higher score after the decimal point.
    # this should usually pick the "standard" variant of a font as long as it
    # doesn't have a special identifier like "regular", "roman", "book", etc.
    # to be fair, with these fonts the old fontconfig method also often fails because
    # it's not clearly defined what the most normal version is for the user.
    # it's therefore better to just have them specify these parts of the name that
    # they think are important. this is especially important for attributes that
    # fall outside of the standard italic / bold distinction like "condensed",
    # "semibold", "oblique", etc.
    final_score = match_score + (1.0 / length(full_name))
    return final_score
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
        italic::Bool=false, # this is unused in the new implementation
        bold::Bool=false, # and this as well
        additional_fonts::String=""
    )
    font_folders = copy(fontpaths())
    # normalized_name = family_name(name)
    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)

    candidates = Pair{FTFont, Float64}[]
    for folder in font_folders
        for font in readdir(folder)
            fpath = joinpath(folder, font)
            face = try_load(fpath)
            face === nothing && continue
            score = match_font(face, name)

            # only take results with net positive character matches into account
            if floor(score) > 0
                push!(candidates, face => score)
            else
                finalize(face) # help gc a bit!
            end
        end
    end
    if !isempty(candidates)
        sort!(candidates; by=last)
        final_candidate = pop!(candidates)
        foreach(x-> finalize(x[1]), candidates)
        return final_candidate[1]
    end
    return nothing
end
