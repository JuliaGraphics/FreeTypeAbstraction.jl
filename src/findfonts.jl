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
    for p in ("/usr/share/fonts", joinpath(homedir(), ".fonts"), joinpath(homedir(), ".local/share/fonts"), "/usr/local/share/fonts",)
            if isdir(p)
                push!(result, p)
                add_recursive(result, p)
            end
        end
        result
    end
end

function family_name(x::FTFont)
    lowercase(x.family_name)
end

function style_name(x::FTFont)
    lowercase(x.style_name)
end

const REGULAR_STYLES = ("regular", "normal", "medium", "standard", "roman", "book")


function match_font(face::FTFont, searchparts)::Tuple{Int, Int, Bool, Int}

    fname = family_name(face)
    sname = style_name(face)
    is_regular_style = any(occursin(s, sname) for s in REGULAR_STYLES)

    fontlength_penalty = -(length(fname) + length(sname))

    family_matches = any(occursin(part, fname) for part in searchparts)

    # return early if family name doesn't have a match
    family_matches || return (0, 0, is_regular_style, fontlength_penalty)

    family_score = sum(length(part) for part in searchparts if occursin(part, fname))

    # now enhance the score with style information
    remaining_parts = filter(part -> !occursin(part, fname), searchparts)

    if isempty(remaining_parts)
        return (family_score, 0, is_regular_style, fontlength_penalty)
    end

    # check if any parts match the style name, otherwise return early
    if !any(occursin(part, sname) for part in remaining_parts)
        return (family_score, 0, is_regular_style, fontlength_penalty)
    end

    style_score = sum(length(part) for part in remaining_parts if occursin(part, sname))

    (family_score, style_score, is_regular_style, fontlength_penalty)
end

function try_load(fpath)
    try
        return FTFont(fpath)
    catch e
        return nothing
    end
end

fontname(ft::FTFont) = "$(family_name(ft)) $(style_name(ft))"

"""
    findfont(
            searchstring::String;
            additional_fonts::String=""
        )

Find a font that matches the specified search string.

Each part of the search string
is searched in the family name first which has to match once to include the font
in the candidate list. For fonts with a family match the style
name is matched next. For fonts with the same family and style name scores, regular
fonts are preferred (any font that is "regular", "normal", "medium", "standard" or "roman")
and as a last tie-breaker, shorter overall font names are preferred.

If the search string precisely matches the name of a valid
font file (with or without extensions "otf" or "ttf"), the
font in that file is selected.

Example:

If we had only four fonts:
- Helvetica Italic
- Helvetica Regular
- Helvetica Neue Regular
- Helvetica Neue Light

Then this is how this function would match different search strings:
- "helvetica"           => Helvetica Regular
- "helv"                => Helvetica Regular
- "HeLvEtIcA"           => Helvetica Regular
- "helvetica italic"    => Helvetica Italic
- "helve ita"           => Helvetica Italic
- "helvetica neue"      => Helvetica Neue Regular
- "tica eue"            => Helvetica Neue Regular
- "helvetica light"     => Helvetica Neue Light
- "light"               => Helvetica Neue Light
- "helvetica bold"      => Helvetica Regular
- "helvetica neue bold" => Helvetica Neue Regular
- "times"               => no match
- "arial"               => no match

File matching:

- "AvenirLTStd-Heavy"     => use the font in file "AvenirLTStd-Heavy.otf"
- "AvenirLTStd-Heavy.otf" => use the font in file "AvenirLTStd-Heavy.otf"

"""
function findfont(
        searchstring::String;
        italic::Bool=false, # this is unused in the new implementation
        bold::Bool=false, # and this as well
        additional_fonts::String=""
    )
    font_folders = copy(fontpaths())

    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)

    # \W splits at all groups of non-word characters (like space, -, ., etc)
    searchparts = unique(split(lowercase(searchstring), r"\W+", keepempty=false))

    candidates = Pair{FTFont, Tuple{Int, Int}}[]

    best_score_so_far = (0, 0, false, typemin(Int))
    best_font = nothing

    found = false

    for folder in font_folders
        for font in readdir(folder)
            fpath = joinpath(folder, font)

            # look for a file that exactly matches the search string (with or without extension)
            filefontname, filefontext = splitext(font)
            if searchstring == font || (searchstring == filefontname && lowercase(filefontext) ∈ (".otf", ".ttf"))
                face = try_load(fpath)
                face === nothing && continue  # not a font
                best_font = face
                found = true
                @debug "found font file $(fpath) to match \"$(searchstring)\""
                break
            end

            face = try_load(fpath)
            face === nothing && continue

            score = match_font(face, searchparts)

            # we can compare all four tuple elements of the score at once
            # in order of importance:

            # 1. number of family match characters
            # 2. number of style match characters
            # 3. is font a "regular" style variant?
            # 4. the negative length of the font name, the shorter the better

            family_match_score = score[1]
            if family_match_score > 0 && score > best_score_so_far
                # finalize previous best font to close the font file
                if !isnothing(best_font)
                    finalize(best_font)
                end

                # new candidate
                best_font = face
                best_score_so_far = score
            else
                finalize(face)
            end
        end
        found && break
    end
    best_font
end
