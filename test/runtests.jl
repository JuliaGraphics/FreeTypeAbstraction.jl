using FreeTypeAbstraction, StaticArrays
using Base.Test

# write your own tests here
face = newface("hack_regular.ttf")

img, metric = renderface(face, 'C')
@test size(img) == (15, 23)
@test typeof(img) == Array{UInt8,2}
@test metric == FontExtent(
	MVector(-8,4),
	MVector(2,23),
	MVector(19,31),
	MVector(15,23)
)
