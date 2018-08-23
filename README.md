# FreeTypeAbstraction

Draw text into a Matrix.

```Julia

using FreeTypeAbstraction

# load a font
face = newface("hack_regular.ttf")

# render a character
img, metric = renderface(face, 'C')

# render a string into an existing matrix
myarray = zeros(UInt8,100,100)
renderstring!(myarray, "hello", face, (10,10), 90, 10, halign=:hright)
```

credits to @aaalexandrov from whom most of the code stems.
