module FreeTypeAbstraction

using FreeType, StaticArrays, Colors, ColorVectorSpace

include("functions.jl")
include("findfonts.jl")

export newface
export renderface
export FontExtent
export kerning
export renderstring!
export findfont

const valid_fontpaths = String[]
fontpaths() = valid_fontpaths

function __init__()
    ft_init()
    atexit(ft_done)
    # This method of finding fonts might not work for exotic platforms,
    # so we supply a way to help it with an environment variable.
    paths = filter(isdir, _font_paths())
    if haskey(ENV, "FREETYPE_ABSTRACTION_FONT_PATH")
        path = ENV["FREETYPE_ABSTRACTION_FONT_PATH"]
        isdir(path) || error("Path in environment variable FREETYPE_ABSTRACTION_FONT_PATH is not a valid directory!")
        push!(paths, path)
    end
    append!(valid_fontpaths, paths)
end

end # module
