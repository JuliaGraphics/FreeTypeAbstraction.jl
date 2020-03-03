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

function family_name(x::FTFont)
    lowercase(x.family_name)
end

function style_name(x::FTFont)
    lowercase(x.style_name)
end


"""
Match a font using the user-specified search string. Each part of the search string
is searched in the family name first which has to match once to include the font
in the candidate list. For fonts with a family match the style
name is matched next. For fonts with the same family and style name scores, regular
fonts are preferred (any font that is "regular", "normal", "medium", "standard" or "roman")
and as a last tie-breaker, shorter overall font names are preferred.


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
"""
function match_font_by_family_and_style(face::FTFont, searchparts)::Tuple{Int, Int}

    fname = family_name(face)

    family_matches = any(occursin(part, fname) for part in searchparts)

    # return early if family name doesn't have a match
    family_matches || return (0, 0)

    # now enhance the score with style information

    remaining_parts = filter(part -> !occursin(part, fname), searchparts)

    family_score = sum(length(part) for part in searchparts if occursin(part, fname))

    # return early if no parts remain for style scoring
    isempty(remaining_parts) && return (family_score, 0)

    sname = style_name(face)

    style_name_matches = any(occursin(part, sname) for part in remaining_parts)

    # return early if no remaining part matches the style name
    style_name_matches || return (family_score, 0)

    style_score = sum(length(part) for part in remaining_parts if occursin(part, sname))

    (family_score, style_score)
end

function try_load(fpath)
    try
        return FTFont(fpath)
    catch e
        return nothing
    end
end

fontname(ft::FTFont) = "$(family_name(ft)) $(style_name(ft))"

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

    for folder in font_folders
        for font in readdir(folder)
            fpath = joinpath(folder, font)
            face = try_load(fpath)
            face === nothing && continue
            family_score, style_score = match_font_by_family_and_style(face, searchparts)
            # only take results with net positive character matches into account
            if family_score > 0
                push!(candidates, face => (family_score, style_score))
            else
                # help gc a bit! Otherwise, this won't end well with the font keeping tons of open files
                finalize(face)
            end
        end
    end

    isempty(candidates) && return nothing

    # sort by family score then style score, highest first
    sort!(candidates; by=x -> x[2], rev = true)


    # best score for comparison
    highscore = candidates[1][2] # tuple{int, int}

    # remove all candidates that have lesser scores than the first one
    for i in 2:length(candidates)
        if candidates[i][2][1] < highscore[1] || candidates[i][2][2] < highscore[2]
            # remove fonts from back to front and finalize them to close
            # their files
            for j in length(candidates):-1:i
                to_remove = pop!(candidates)[1]
                finalize(to_remove)
            end
            # there will be no other i's we need to check after this
            break
        end
    end

    # return early if only one font remains
    length(candidates) == 1 && return candidates[1][1]

    # there is still more than one candidate
    # all candidates have the same family and style score

    # prefer regular fonts among the remaining options
    regular_styles = ("regular", "normal", "medium", "standard", "roman")
    regular_matches = filter(candidates) do c
        any(occursin(style, style_name(c[1])) for style in regular_styles)
    end

    # if any fonts match a regular-type style name, choose the overall shortest
    if !isempty(regular_matches)

        sort!(regular_matches,
            by = c -> length(fontname(c[1])))

        shortest = regular_matches[1][1]

        # close all non-used font files
        for c in candidates
            if c[1] !== shortest
                finalize(c)
            end
        end

        return shortest
    end

    # we didn't find any font with a "regular" name
    # as a last heuristic, we just choose the font with the shortest name

    sort!(candidates,
        by = c -> length(fontname(c[1])))

    shortest = candidates[1][1]

    # close all non-used font files
    for c in candidates
        if c[1] !== shortest
            finalize(c)
        end
    end

    shortest
end
