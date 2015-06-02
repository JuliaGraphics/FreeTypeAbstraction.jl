using FreeFontAbstraction
using Base.Test

# write your own tests here
FreeFontAbstraction.init()

face 	= newface("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
img, metric = renderface(face, 'C')
println(size(img))
println(typeof(img))
println(metric)


FreeFontAbstraction.done()