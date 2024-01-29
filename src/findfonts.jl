if Sys.isapple()
    function _font_paths()
        return [
            "/Library/Fonts", # Additional fonts that can be used by all users. This is generally where fonts go if they are to be used by other applications.
            joinpath(homedir(), "Library/Fonts"), # Fonts specific to each user.
            "/Network/Library/Fonts", # Fonts shared for users on a network
            "/System/Library/Fonts", # System specific fonts
            "/System/Library/Fonts/Supplemental", # new location since Catalina
        ]
    end
elseif Sys.iswindows()
    function _font_paths()
        return [
            joinpath(get(ENV, "SYSTEMROOT", "C:\\Windows"), "Fonts"),
            joinpath(homedir(), "AppData", "Local", "Microsoft", "Windows", "Fonts"),
        ]
    end
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
        for p in (
            "/usr/share/fonts",
            joinpath(homedir(), ".fonts"),
            joinpath(homedir(), ".local/share/fonts"),
            "/usr/local/share/fonts"
        )
            if isdir(p)
                push!(result, p)
                add_recursive(result, p)
            end
        end
        return result
    end
end

family_name(x::FTFont) = lowercase(x.family_name)
style_name(x::FTFont) = lowercase(x.style_name)

const REGULAR_STYLES = ("regular", "normal", "medium", "standard", "roman", "book")

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
function match_font(face::FTFont, searchparts)::Tuple{Int, Int, Bool, Int}
    fname = family_name(face)
    sname = style_name(face)
    is_regular_style = any(occursin(s, sname) for s in REGULAR_STYLES)

    fontlength_penalty = -(length(fname) + length(sname))

    family_matches = any(occursin(part, fname) for part in searchparts)

    # return early if family name doesn't have a match
    family_matches || return (0, 0, is_regular_style, fontlength_penalty)

    family_score, style_score = 0, 0
    for (i, part) in enumerate(Iterators.reverse(searchparts))
        if occursin(part, fname)
            family_score += i + length(part)
        elseif occursin(part, sname)
            style_score += i + length(part)
        end
    end

    return (family_score + style_score, family_score, is_regular_style, fontlength_penalty)
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

    max_score1 = sum(length, searchparts) + sum(1:length(searchparts))
    best_1i, best_file, best_score = 0, nothing, (0, 0, false, typemin(Int))
    fontfiles = fontfiles_guess_sorted(searchparts; additional_fonts)
    for (i, fontfile) in enumerate(fontfiles)
        face = try_load(fontfile)
        face === nothing && continue
        # we can compare all four tuple elements of the score at once
        # in order of importance:
        # 1. number of family and style match characters (with priority factor)
        # 2. number of family match characters  (with priority factor)
        # 3. is font a "regular" style variant?
        # 4. the negative length of the font name, the shorter the better
        score = match_font(face, searchparts)
        if first(score) > 0 && score >= best_score
            best_1i = i
            if score > best_score
                best_file, best_score = fontfile, score
            end
        elseif first(best_score) == max_score1 && first(score) < first(best_score) && i > 2 * best_1i
            return best_font
        end
    end
    best_font
end

"""
    fontfiles_guess_sorted(searchparts::Vector{<:AbstractString}; additional_fonts::String="")

Collect all font files under `fontpaths` (also including `additional_fonts` if
non-empty), and then rank them by how closely we think the font information
matches `searchparts`, guessing based on the font file name.
"""
function fontfiles_guess_sorted(searchparts::Vector{<:AbstractString}; additional_fonts::String="")
    fontfile_names = Dict{String, String}()
    function score_names(searchparts, fontfile)
        filename = get!(() -> splitext(basename(fontfile)) |> first |> lowercase,
                        fontfile_names, fontfile) # Caching produces a ~7x speedup
        # We sum the length of the search parts found in `filename` with a reverse part
        # index (`i`) to weight earlier matching parts higher.  This is essentially
        # an approximation of the more sophisticated (and expensive) scoring performed
        # in `match_font`.
        sum((i + length(part) for (i, part) in enumerate(Iterators.reverse(searchparts))
                 if occursin(part, filename)),
            init=0), -length(filename)
    end
    font_folders = copy(fontpaths())
    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)
    searchparts = copy(searchparts)
    push!(searchparts, String(map(first, searchparts)))
    allfonts = String[]
    for folder in font_folders
        append!(allfonts, readdir(folder, join=true))
    end
    sort(allfonts, by=Base.Fix1(score_names, searchparts), rev=true)
end
