using FreeTypeAbstraction, StaticArrays, Colors, ColorVectorSpace
using Test
using FreeTypeAbstraction: Vec

face = newface(joinpath(@__DIR__, "hack_regular.ttf"))
f = unsafe_load(face[])

img, metric = renderface(face, 'C')
@test size(img) == (15, 23)
@test typeof(img) == Array{UInt8,2}
@test metric == FontExtent(
    Vec(-8,4),
    Vec(2,23),
    Vec(19,31),
    Vec(15,23)
)

a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 10)
@test any(a[3:12,:] .!= 0)
@test all(a[vcat(1:2,13:20),:] .== 0)
@test any(a[:,11:40] .!= 0)
@test all(a[:,vcat(1:10,41:100)] .== 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 15, 70)
@test any(a[8:17,:] .!= 0)
@test all(a[vcat(1:7,18:20),:] .== 0)
@test any(a[:,71:100] .!= 0)
@test all(a[:,1:70] .== 0)

a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vtop)
@test all(a[1:10,:] .== 0)
@test any(a[11:20,:] .!= 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vcenter)
@test all(a[vcat(1:5,16:end),:] .== 0)
@test any(a[6:15,:] .!= 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vbaseline)
@test all(a[vcat(1:2,13:end),:] .== 0)
@test any(a[3:12,:] .!= 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, valign=:vbottom)
@test any(a[1:10,:] .!= 0)
@test all(a[11:20,:] .== 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, halign=:hleft)
@test all(a[:,1:50] .== 0)
@test any(a[:,51:100] .!= 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, halign=:hcenter)
@test all(a[:,vcat(1:35,66:end)] .== 0)
@test any(a[:,36:65] .!= 0)
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, halign=:hright)
@test any(a[:,1:50] .!= 0)
@test all(a[:,51:100] .== 0)

a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, fcolor=0x80)
@test maximum(a)<=0x80
a = renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 10, 50, fcolor=0x80, bcolor=0x40)
@test any(a .== 0x40)
a = renderstring!(fill(0x01,20,100), "helgo", face, (10,10), 10, 50, bcolor=nothing)
@test !any(a .== 0x00)

a = renderstring!(zeros(Float32,20,100), "helgo", face, (10,10), 10, 50)
@test maximum(a) <= 1.0
a = renderstring!(zeros(Float64,20,100), "helgo", face, (10,10), 10, 50)
@test maximum(a) <= 1.0

renderstring!(zeros(Gray,20,100), "helgo", face, (10,10), 10, 50)
renderstring!(zeros(Gray{Float64},20,100), "helgo", face, (10,10), 10, 50, fcolor=Gray(0.5))

renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 0, 0, halign=:hcenter, valign=:vcenter)
renderstring!(zeros(UInt8,20,100), "helgo", face, (10,10), 25, 80)

# Find fonts
# these fonts should be available on all platforms:

# debug travis... does it even have fonts?
fontpaths = FreeTypeAbstraction.fontpaths()

isempty(fontpaths) && println("OS doesn't have any font folder")

if Sys.islinux()
    fonts = [
        "dejavu sans",
    ]
else # OSX + windows have some more fonts installed per default
    fonts = [
        "Times New Roman",
        "Arial",
        "Comic Sans MS",
        "Impact",
        "Tahoma",
        "Trebuchet MS",
        "Verdana",
        "Courier New",
    ]
end

@testset "finding fonts" begin

    for font in fonts
        @testset "finding $font" begin
            @test findfont(font) != nothing
        end
    end
    @testset "find in additional dir" begin
        @test findfont("Hack") == nothing
        @test findfont("Hack", additional_fonts = @__DIR__) != nothing
    end
end


@testset "loading lots of fonts" begin
    for i = 1:10
        for font in fonts
            @time findfont(font)
        end
    end
    @test "No Error" == "No Error"
end
