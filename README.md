[![codecov](https://codecov.io/gh/JuliaGraphics/FreeTypeAbstraction.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaGraphics/FreeTypeAbstraction.jl)

[![Build Status](https://travis-ci.org/JuliaGraphics/FreeTypeAbstraction.jl.svg?branch=master)](https://travis-ci.org/JuliaGraphics/FreeTypeAbstraction.jl)

# FreeTypeAbstraction

Draw text into a Matrix.

```Julia

using FreeTypeAbstraction

# load a font
face = FTFont("hack_regular.ttf")

# render a character
img, metric = renderface(face, 'C')

# render a string into an existing matrix
myarray = zeros(UInt8, 100, 100)
pixelsize = 10
x0, y0 = 90, 10
renderstring!(myarray, "hello", face, pixelsize, x0, y0, halign=:hright)

# find fonts

f = findfont("helv bo")
f.family_name * " " * f.style_name
# => "Helvetica LT Std Bold"

f = findfont("Ari")
f.family_name * " " * f.style_name
# => "Arial Unicode MS Regular"
```

credits to @aaalexandrov from whom most of the early code comes.
