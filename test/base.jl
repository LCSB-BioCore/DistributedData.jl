
@testset "Base functions" begin

    @testset "Distributed data transfers -- local" begin
        data = rand(5)
        save_at(1, :test, data)

        @test fetch(get_from(1, :test)) == data
        @test get_val_from(1, :test) == data

        remove_from(1, :test)

        @test sizeof(get_val_from(1, :test)) == 0 #should be "nothing" but this is more generic
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

        undistribute(:test, W)

        @test sum([sizeof(get_val_from(w, :test)) for w in W]) == 0
    end

    @testset "Data distribution" begin
        d = rand(100, 5)

        di = distribute_array(:test, d, W)

        @test di.val == :test
        @test Set(di.workers) == Set(W)
        @test begin
            d1 = get_val_from(di.workers[1], :test)
            d1 == d[1:size(d1, 1), :]
        end

        #TODO test actual sizes of the distributed pieces

        @test distributed_collect(di, free = false) == d #TODO test with true
        @test sum([sizeof(get_val_from(w, :test)) for w in W]) > 0
        undistribute(di)
        @test sum([sizeof(get_val_from(w, :test)) for w in W]) == 0
    end

    @testset "Distributed computation" begin
        di = distributed_transform(:(), x -> rand(5), W, :test)

        @test get_val_from(W[1], :test) == distributed_collect(di)[1:5]

        orig = distributed_collect(di)

        @test isapprox(
            distributed_mapreduce(:test, d -> sum(d .^ 2), (a, b) -> a + b, W),
            sum(orig .^ 2),
        )

        distributed_transform(di, d -> d .* 2)

        @test orig .* 2 == distributed_collect(:test, W)

        @test isapprox(
            distributed_mapreduce(di, d -> sum(d .^ 2), (a, b) -> a + b),
            sum((orig .* 2) .^ 2),
        )

        t = zeros(length(W))
        exp = zeros(length(W))

        t[1] = 2
        exp[1] = sum(2 .* get_val_from(W[1], :test))

        @test distributed_foreach(t, (i) -> eval(:(sum($i .* $(di.val)))), W) == exp

        undistribute(di)

        @test distributed_mapreduce(:noname, x -> x, (a, b) -> a + b, []) == nothing
    end

    @testset "Internal utilities" begin
        @test DiDa.tmpSym(:test) != :test
        @test DiDa.tmpSym(:test, prefix = "abc", suffix = "def") == :abctestdef
        @test DiDa.tmpSym(Dinfo(:test, W)) != :test
    end

    @testset "Persistent distributed data" begin
        di = distributed_transform(:(), x -> rand(5), W, :test)

        files = DiDa.defaultFiles(di.val, di.workers)
        @test allunique(files)

        orig = distributed_collect(di)
        distributed_export(di, files)
        distributed_transform(di, x -> "erased")
        distributed_import(di, files)

        @test orig == distributed_collect(di)

        distributed_export(di.val, di.workers, files)
        di2 = distributed_import(:test2, di.workers, files)

        @test orig == distributed_collect(di2)

        undistribute(di)
        undistribute(di2)

        distributed_unlink(di)

        @test all([!isfile(f) for f in files])
    end

    rmprocs(W)
    W = nothing

end
