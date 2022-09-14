module FreeTypeAbstraction

using FreeType, Colors, ColorVectorSpace, GeometryBasicsCore
using Base.Iterators: Repeated, repeated
import Base: /, *, ==

import Base.Broadcast: BroadcastStyle, Style, broadcasted
import GeometryBasicsCore: StaticVector

include("types.jl")
include("findfonts.jl")
include("layout.jl")
include("rendering.jl")

# types
export FTFont, FontExtent

# methods
export newface, renderface, kerning, renderstring!, findfont

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

if Base.VERSION >= v"1.4.2"
    include("precompile.jl")
    _precompile_()
end

end # module
