family_name(x::FTFont) = lowercase(x.family_name)
style_name(x::FTFont) = lowercase(x.style_name)

const REGULAR_STYLES = ("regular", "normal", "standard", "book", "roman", "medium")
const FONT_EXTENSION_PRIORITY = ("otc", "otf", "ttc", "ttf", "cff", "woff2", "woff", "pfa", "pfb", "pfr", "fnt", "pcf", "bdf")

"""
    score_font(searchparts::Vector{<:AbstractString}, fontpath::String)
    score_font(searchparts::Vector{<:AbstractString}, family::String, style::String, ext::String)

Score a font match using the list user-specified `searchparts`. The font match
can either be a path to a font file (`fontpath`), or a `family`, `style`, and
`ext`.

Each part of the search string is searched in the family name first which has to
match once to include the font in the candidate list. For fonts with a family
match the style name is matched next. For fonts with the same family and style
name scores, regular fonts are preferred (any font that is "regular", "normal",
"medium", "standard" or "roman") and as a last tie-breaker, shorter overall font
names are preferred.

## Example:

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
function score_font(searchparts::Vector{<:AbstractString}, family::String, style::String, ext::String)::Tuple{Int, Int, Int, Int, Int}
    regularity = minimum((length(REGULAR_STYLES) + 1 - findfirst(==(regsty), REGULAR_STYLES)::Int
                          for regsty in REGULAR_STYLES if occursin(regsty, style)), init=typemax(Int))
    if regularity == typemax(Int)
        regularity = 0
    end
    ext_priority = length(FONT_EXTENSION_PRIORITY) - something(findfirst(==(ext), FONT_EXTENSION_PRIORITY), -1)

    fontlength_penalty = -(length(family) + length(style))

    # return early if family name doesn't have a match
    any(occursin(part, family) for part in searchparts) ||
        return (0, 0, regularity, fontlength_penalty, ext_priority)

    family_score, style_score = 0, 0
    for (i, part) in enumerate(Iterators.reverse(searchparts))
        if occursin(part, family)
            family_score += i + length(part)
        elseif occursin(part, style)
            style_score += i + length(part)
        end
    end

    return (family_score + style_score, family_score, regularity, fontlength_penalty, ext_priority)
end

function score_font(searchparts::Vector{<:AbstractString}, fontpath::String)::Tuple{Int, Int, Int, Int, Int}
    if (finfo = font_info(fontpath)) |> !isnothing
        score_font(searchparts, finfo.family, finfo.style, finfo.ext)
    else
        (0, 0, 0, typemin(Int), length(FONT_EXTENSION_PRIORITY)+1)
    end
end

const FONTINFO_CACHE = Dict{String, Union{NamedTuple{(:family, :style, :ext), Tuple{String, String, String}}, Nothing}}()

function font_info(fontpath::String)
    if isfile(fontpath)
        get!(FONTINFO_CACHE, fontpath) do
            font = try_load(fontpath)
            font === nothing && return
            family = family_name(font)
            style = style_name(font)
            finalize(font)
            (; family=family, style=style, ext=last(split(fontpath, '.')))
        end
    end
end

function try_load(fpath)
    try
        return FTFont(fpath)
    catch e
        return nothing
    end
end
try_load(::Nothing) = nothing

fontname(ft::FTFont) = "$(family_name(ft)) $(style_name(ft))"

const FONT_CACHE = Dict{String, Tuple{Float64, Union{String, Nothing}}}()

function findfont(
        searchstring::String;
        italic::Bool=false, # this is unused in the new implementation
        bold::Bool=false, # and this as well
        additional_fonts::String=""
    )
    font_folders = copy(fontpaths())
    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)

    font_folders = copy(fontpaths())
    isempty(additional_fonts) || pushfirst!(font_folders, additional_fonts)
    filter!(isdir, font_folders)
    folder_max_mtime = maximum(mtime, font_folders)

    if haskey(FONT_CACHE, searchstring)
        cache_mtime, fontfile = FONT_CACHE[searchstring]
        cache_mtime == folder_max_mtime && return try_load(fontfile)
    end
    _, fontfile = FONT_CACHE[searchstring] = (folder_max_mtime, findfont_nocache(searchstring, font_folders))
    if !isnothing(fontfile)
        try_load(fontfile)
    end
end

function findfont_nocache(searchstring::String, fontfolders::Vector{<:AbstractString})
    # \W splits at all groups of non-word characters (like space, -, ., etc)
    searchparts = unique(split(lowercase(searchstring), r"\W+", keepempty=false))
    max_score1 = sum(length, searchparts) + sum(1:length(searchparts))
    best_file, best_score = nothing, (0, 0, 0, typemin(Int), 0)
    for folder in fontfolders, fontfile in readdir(folder, join=true)
        # we can compare all five tuple elements of the score at once
        # in order of importance:
        # 1. number of family and style match characters (with priority factor)
        # 2. number of family match characters  (with priority factor)
        # 3. is font a "regular" style variant?
        # 4. the negative length of the font name, the shorter the better
        # 5. the font file extension priority
        score = score_font(searchparts, fontfile)
        if first(score) > 0 && score > best_score
            best_file, best_score = fontfile, score
        end
    end
    best_file
end
