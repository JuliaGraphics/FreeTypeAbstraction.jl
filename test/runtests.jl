using FreeTypeAbstraction, StaticArrays, Colors, ColorVectorSpace
using Base.Test

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

a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 10)
@test any(a[3:12,:].!=0)
@test all(a[vcat(1:2,13:20),:].==0)
@test any(a[:,11:40].!=0)
@test all(a[:,vcat(1:10,41:100)].==0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 15, 70)
@test any(a[8:17,:].!=0)
@test all(a[vcat(1:7,18:20),:].==0)
@test any(a[:,71:100].!=0)
@test all(a[:,1:70].==0)

a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vtop)
@test all(a[1:10,:].==0)
@test any(a[11:20,:].!=0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vcenter)
@test all(a[vcat(1:5,16:end),:].==0)
@test any(a[6:15,:].!=0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vbaseline)
@test all(a[vcat(1:2,13:end),:].==0)
@test any(a[3:12,:].!=0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vbottom)
@test any(a[1:10,:].!=0)
@test all(a[11:20,:].==0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, halign=:hleft)
@test all(a[:,1:50].==0)
@test any(a[:,51:100].!=0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, halign=:hcenter)
@test all(a[:,vcat(1:35,66:end)].==0)
@test any(a[:,36:65].!=0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, halign=:hright)
@test any(a[:,1:50].!=0)
@test all(a[:,51:100].==0)

a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, fcolor=0x80)
@test maximum(a)<=0x80
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, fcolor=0x80, bcolor=0x40)
@test any(a.==0x40)
a = renderstring!(fill(0x01,20,100), "helgo", face, (10,10), 10, 50, bcolor=nothing)
@test !any(a.==0x00)

a = renderstring!(zeros(Float32,20,100), "helgo", face, (10,10), 10, 50)
@test maximum(a)<=1.0
a = renderstring!(zeros(Float64,20,100), "helgo", face, (10,10), 10, 50)
@test maximum(a)<=1.0

a = renderstring!(zeros(Gray,20,100), "helgo", face, (10,10), 10, 50)
a = renderstring!(zeros(Gray{Float64},20,100), "helgo", face, (10,10), 10, 50, fcolor=Gray(0.5))
