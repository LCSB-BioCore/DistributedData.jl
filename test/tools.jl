
@testset "High-level tools" begin

    W = addprocs(2)
    @everywhere using DiDa

    Random.seed!(1)
    dd = rand(11111, 5)
    buckets = rand([1, 2, 3], 11111)

    di1 = scatter_array(:test1, dd, W[1:1])
    di2 = scatter_array(:test2, dd, W)
    buckets1 = scatter_array(:buckets1, buckets, W[1:1])
    buckets2 = scatter_array(:buckets2, buckets, W)

    @testset "Distribution works as expected" begin
        @test gather_array(di1) == dd
        @test gather_array(di2) == dd
    end

    subsel = [1, 3, 4]
    dd = dd[:, subsel]
    dselect(di1, subsel)
    dselect(di2, subsel)

    @testset "dapply_cols, dapply_rows" begin
        diV = scatter_array(:testV, dd, W[1:1])
        diH = scatter_array(:testH, Matrix(dd'), W[1:1])
        dapply_cols(diV, (x, _) -> x ./ sum(x), Vector(1:3))
        dapply_rows(diH, x -> x ./ sum(x))
        @test isapprox(gather_array(diV), Matrix(gather_array(diH)'))
        unscatter(diV)
        unscatter(diH)
    end

    @testset "dselect" begin
        @test gather_array(di1) == dd
        @test gather_array(di2) == dd
    end

    di3 = dcopy(di2, :test3)

    @testset "dcopy" begin
        @test di2.workers == di3.workers
        @test dd == gather_array(di3)
    end

    unscatter(di3)

    (means1, sds1) = dstat(di1, [1, 3])
    (means2, sds2) = dstat(di2, [1, 3])

    @testset "dstat" begin
        @test length(means1) == 2
        @test length(sds1) == 2
        @test isapprox(means1, means2, atol = 1e-8)
        @test isapprox(sds1, sds2, atol = 1e-8)
        @test all([isapprox(0.5, m, atol = 0.1) for m in means1])
        @test all([isapprox(0.29, s, atol = 0.1) for s in sds1])
    end

    medians1 = dmedian(di1, [1, 3])
    medians2 = dmedian(di2, [1, 3])

    @testset "dmedian" begin
        @test length(medians1) == 2
        @test isapprox(medians1, medians2, atol = 1e-4)
        @test all([isapprox(0.5, m, atol = 0.1) for m in medians1])
    end

    (bmeans1, bsds1) = dstat_buckets(di1, 3, buckets1, [1, 3])
    (bmeans2, bsds2) = dstat_buckets(di2, 3, buckets2, [1, 3])

    @testset "bucketed dstat" begin
        @test size(bmeans1) == (3, 2)
        @test size(bsds1) == (3, 2)
        @test isapprox(bmeans1, bmeans2, atol = 1e-8)
        @test isapprox(bsds1, bsds2, atol = 1e-8)
        @test all([isapprox(0.5, m, atol = 0.1) for m in bmeans1])
        @test all([isapprox(0.29, s, atol = 0.1) for s in bsds1])
    end

    medians1 = dmedian_buckets(di1, 3, buckets1, [1, 3])
    medians2 = dmedian_buckets(di2, 3, buckets2, [1, 3])

    @testset "dmedian" begin
        @test size(medians1) == (3, 2)
        @test isapprox(medians1, medians2, atol = 1e-4)
        @test all([isapprox(0.5, m, atol = 0.1) for m in medians1])
    end

    dscale(di1, [2, 3])
    dscale(di2, [2, 3])
    (means1, sds1) = dstat(di1, [1, 2, 3])
    (means2, sds2) = dstat(di2, [1, 2, 3])

    @testset "dscale" begin
        @test isapprox(means1, means2, atol = 1e-8)
        @test isapprox(sds1, sds2, atol = 1e-8)
        @test isapprox(0.5, means1[1], atol = 0.1)
        @test all([isapprox(0.0, m, atol = 1e-3) for m in means1[2:3]])
        @test all([isapprox(1.0, s, atol = 1e-3) for s in sds1[2:3]])
    end

    unscatter(di1)
    unscatter(di2)
    rmprocs(W)

    d = ones(Float64, 2, 2)
    di = scatter_array(:test, d, [1])
    dscale(di, [1, 2])
    @testset "dscale does not produce NaNs on sdev==0" begin
        @test gather_array(di) == zeros(Float64, 2, 2)
    end
    unscatter(di)

end
