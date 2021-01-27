
using Test
using DistributedData, Distributed, Random

@testset "DistributedData tests" begin
    include("base.jl")
    include("tools.jl")
end
