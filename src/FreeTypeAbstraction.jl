__precompile__()

module FreeTypeAbstraction

using FreeType, StaticArrays, Colors, ColorVectorSpace

include("functions.jl")

export newface
export renderface
export FontExtent
export kerning
export renderstring!

function __init__()
    ft_init()
    atexit(ft_done)
end

end # module
