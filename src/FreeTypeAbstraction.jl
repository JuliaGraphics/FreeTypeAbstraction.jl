VERSION >= v"0.4.0-dev+6521" && __precompile__(true)

module FreeTypeAbstraction

using FreeType, FixedSizeArrays

include("functions.jl")

#export init -> not exported, so call FreeFontAbstraction.init() /done()
#export done

export newface
export renderface
export FontExtent
export kerning
end # module
