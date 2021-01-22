
@testset "Base functions" begin

    @testset "Distributed data transfers -- local" begin
        data = rand(5)
        save_at(1, :test, data)

        @test fetch(get_from(1, :test)) == data
        @test get_val_from(1, :test) == data

        remove_from(1, :test)

        @test sizeof(get_val_from(1, :test)) == 0 #should be "nothing" but this is more generic and generally describes what we want
    end

    addprocs(3)
    @everywhere using DiDa
    W = workers()

    @testset "Distributed data transfers -- with workers" begin
        data = [rand(5) for i in W]
        for (i, w) in enumerate(W)
            save_at(w, :test, data[i])
        end

        @test [fetch(get_from(w, :test)) for w in W] == data
        @test [get_val_from(w, :test) for w in W] == data

        unscatter(:test, W)

        @test sum([sizeof(get_val_from(w, :test)) for w in W]) == 0
    end

    @testset "Data distribution" begin
        d = rand(100, 5)

        di = scatter_array(:test, d, W)

        @test di.val == :test
        @test Set(di.workers) == Set(W)
        @test begin
            d1 = get_val_from(di.workers[1], :test)
            d1 == d[1:size(d1, 1), :]
        end

        #TODO test actual sizes of the distributed pieces

        @test gather_array(di, free = false) == d #TODO test with true
        @test sum([sizeof(get_val_from(w, :test)) for w in W]) > 0
        unscatter(di)
        @test sum([sizeof(get_val_from(w, :test)) for w in W]) == 0
    end

    @testset "Distributed computation" begin
        di = dtransform(:(), x -> rand(5), W, :test)

        @test get_val_from(W[1], :test) == gather_array(di)[1:5]

        orig = gather_array(di)

        @test isapprox(
            dmapreduce(:test, d -> sum(d .^ 2), (a, b) -> a + b, W),
            sum(orig .^ 2),
        )

        dtransform(di, d -> d .* 2)

        @test orig .* 2 == gather_array(:test, W)

        @test isapprox(
            dmapreduce(di, d -> sum(d .^ 2), (a, b) -> a + b),
            sum((orig .* 2) .^ 2),
        )

        t = zeros(length(W))
        exp = zeros(length(W))

        t[1] = 2
        exp[1] = sum(2 .* get_val_from(W[1], :test))

        @test dmap(t, (i) -> eval(:(sum($i .* $(di.val)))), W) == exp

        unscatter(di)

        @test dmapreduce(:noname, x -> x, (a, b) -> a + b, []) == nothing
    end

    @testset "Internal utilities" begin
        @test DiDa.tmp_symbol(:test) != :test
        @test DiDa.tmp_symbol(:test, prefix = "abc",
                                     suffix = "def") == :abctestdef
        @test DiDa.tmp_symbol(Dinfo(:test, W)) != :test
    end

    @testset "Persistent distributed data" begin
        di = dtransform(:(), x -> rand(5), W, :test)

        files = DiDa.defaultFiles(di.val, di.workers)
        @test allunique(files)

        orig = gather_array(di)
        dstore(di, files)
        dtransform(di, x -> "erased")
        dload(di, files)

        @test orig == gather_array(di)

        dstore(di.val, di.workers, files)
        di2 = dload(:test2, di.workers, files)

        @test orig == gather_array(di2)

        unscatter(di)
        unscatter(di2)

        dunlink(di)

        @test all([!isfile(f) for f in files])
    end

    rmprocs(W)
    W = nothing

end
