module FreeTypeAbstraction

using FreeType, Colors, ColorVectorSpace, GeometryBasics
using Base.Iterators: Repeated, repeated
import Base: /, *, ==, @lock
import Base.Broadcast: BroadcastStyle, Style, broadcasted
using GeometryBasics: StaticVector
using BaseDirs
import Mmap

include("types.jl")
include("findfonts.jl")
include("layout.jl")
include("rendering.jl")

export FTFont
export newface
export renderface
export FontExtent
export kerning
export renderstring!
export findfont

const valid_fontpaths = String[]
fontpaths() = valid_fontpaths

# `isdir`, `realpath` and `readdir` throw for a path that cannot be followed, such as a
# symlink loop (ELOOP) or a folder without read permission; treat it as no folder.
function try_io(f, path)
    try
        return f(path)
    catch e
        e isa Base.IOError || rethrow()
        return nothing
    end
end

"""
    font_subdirs(roots)

The folders in `roots` and every folder below them, breadth first. Each folder is listed
once, so a symlink back to a folder already found ends the descent instead of looping, and
paths that cannot be followed are skipped.
"""
function font_subdirs(roots)
    found = String[]
    seen = Set{String}()
    queue = collect(String, roots)
    while !isempty(queue)
        path = popfirst!(queue)
        try_io(isdir, path) === true || continue
        real = try_io(realpath, path)
        (real === nothing || real in seen) && continue
        push!(seen, real)
        push!(found, path)
        entries = try_io(p -> readdir(p; join=true), path)
        entries === nothing || append!(queue, entries)
    end
    return found
end

function __init__()
    ft_init()
    atexit(ft_done)
    roots = BaseDirs.fonts(existent=true)
    @static if Sys.isunix() && !Sys.isapple()
        append!(valid_fontpaths, font_subdirs(roots))
    else
        append!(valid_fontpaths, roots)
    end
    # This method of finding fonts might not work for exotic platforms,
    # so we supply a way to help it with an environment variable.
    if haskey(ENV, "FREETYPE_ABSTRACTION_FONT_PATH")
        path = ENV["FREETYPE_ABSTRACTION_FONT_PATH"]
        isdir(path) || error("Path in environment variable FREETYPE_ABSTRACTION_FONT_PATH is not a valid directory!")
        push!(valid_fontpaths, path)
    end
end

if Base.VERSION >= v"1.4.2"
    include("precompile.jl")
    _precompile_()
end

end # module
