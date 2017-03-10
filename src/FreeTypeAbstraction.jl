VERSION >= v"0.4.0-dev+6521" && __precompile__()

module FreeTypeAbstraction

using FreeType, FixedSizeArrays

include("functions.jl")

export newface
export renderface
export FontExtent
export kerning

function __init__()
    ft_init()
    atexit(ft_done)
end

end # module
