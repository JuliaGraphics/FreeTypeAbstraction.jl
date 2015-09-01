using FreeTypeAbstraction, FixedSizeArrays
using Base.Test

# write your own tests here
FreeTypeAbstraction.init()

face = newface("hack_regular.ttf")

img, metric = renderface(face, 'C')
@test size(img) == (15, 23)
@test typeof(img) == Array{UInt8,2}
@test metric == FontExtent(
	Vec(-8,4),
	Vec(2,23),
	Vec(19,31),
	Vec(15,23)
)

FreeTypeAbstraction.done()