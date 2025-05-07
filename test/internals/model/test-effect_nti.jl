@testset "Effect of competition on net growth rate" begin
    foodweb = FoodWeb([0 0 0; 0 0 0; 1 1 0])

    # If network is a FoodWeb, expect no effect on G_net
    for G_net in 1:10
        @test Internals.effect_competition(G_net, nothing, nothing, foodweb) == G_net
    end

    multi_net = MultiplexNetwork(foodweb; C_competition = 1.0)
    B = [2.0, 1, 1]
    for G_net in 1:10
        # Low intensity
        for c0 in [0.1, 0.2, 0.3]
            multi_net.layers[:competition].intensity = c0
            @test Internals.effect_competition(G_net, 1, B, multi_net) ==
                  G_net * (1 - c0 * 1)
            @test Internals.effect_competition(G_net, 2, B, multi_net) ==
                  G_net * (1 - c0 * 2)
            @test Internals.effect_competition(G_net, 3, B, multi_net) == G_net
        end
        # Strong intensity
        for c0 in [1, 2, 3]
            multi_net.layers[:competition].intensity = c0
            @test Internals.effect_competition(G_net, 1, B, multi_net) == 0
            @test Internals.effect_competition(G_net, 2, B, multi_net) == 0
            @test Internals.effect_competition(G_net, 3, B, multi_net) == G_net
        end
    end

    # If G_net is negative, no effect
    G_net = -1
    @test Internals.effect_competition(G_net, 1, B, multi_net) == G_net
    @test Internals.effect_competition(G_net, 2, B, multi_net) == G_net
    @test Internals.effect_competition(G_net, 3, B, multi_net) == G_net

    # Custom functional form
    multi_net.layers[:competition].f = (x, δx) -> x * (1 - δx^2)
    B = [2.0, 1, 1]
    for G in 1:10
        for c0 in [0.1, 0.2, 0.3]
            multi_net.layers[:competition].intensity = c0
            @test Internals.effect_competition(G, 1, B, multi_net) == G * (1 - (c0 * 1)^2)
            @test Internals.effect_competition(G, 2, B, multi_net) == G * (1 - (c0 * 2)^2)
            @test Internals.effect_competition(G, 3, B, multi_net) == G
        end
    end
end


@testset "Effect of facilitation on intrinsic growth rate" begin
    foodweb = FoodWeb([0 0; 1 0])
    multi_net = MultiplexNetwork(foodweb; C_facilitation = 1.0)

    # Default intensity: f0 = 1.0
    @test Internals.effect_facilitation(1, 1, [1, 0], multi_net) == 1
    @test Internals.effect_facilitation(10, 1, [1, 0], multi_net) == 10
    @test Internals.effect_facilitation(10, 1, [1, 1], multi_net) == 20
    @test Internals.effect_facilitation(10, 1, [1, 2], multi_net) == 30

    # Non default intensity: f0 = 5.0
    multi_net.layers[:facilitation].intensity = 5.0
    @test Internals.effect_facilitation(1, 1, [1, 0], multi_net) == 1
    @test Internals.effect_facilitation(10, 1, [1, 0], multi_net) == 10
    @test Internals.effect_facilitation(10, 1, [1, 1], multi_net) == 60
    @test Internals.effect_facilitation(10, 1, [1, 2], multi_net) == 110

    # Custom functional form
    multi_net.layers[:facilitation].f = (x, δx) -> x * (1 + 2 * δx) # fac. effect 2x stronger
    @test Internals.effect_facilitation(1, 1, [1, 0], multi_net) == 1
    @test Internals.effect_facilitation(10, 1, [1, 0], multi_net) == 10
    @test Internals.effect_facilitation(10, 1, [1, 1], multi_net) == 110
    @test Internals.effect_facilitation(10, 1, [1, 2], multi_net) == 210
end

@testset "Effect of refuge on attack rate" begin

    # 1 refuge link
    B = [1.0, 1, 1]
    for aᵣ in [0.1, 0.2, 0.3, 0.4, 0.5], r0 in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]
        net_refuge.layers[:refuge].intensity = r0
        aᵣ_matrix = sparse([0 0 0; aᵣ 0 0; aᵣ aᵣ 0])
        aᵣ_refuge_matrix = sparse([0 0 0; aᵣ 0 0; aᵣ aᵣ/(1+r0) 0])
        @test Internals.effect_refuge(aᵣ_matrix, B, net_refuge) == aᵣ_refuge_matrix
    end

    # 2 refuge links
    A_refuge = sparse(Bool[0 1 1 0; 1 0 1 0; 0 0 0 0; 0 0 0 0])
    foodweb = FoodWeb(niche_model, 4; C = 0.3)
    net = MultiplexNetwork(foodweb; A_refuge = A_refuge)
    B = [1.0, 2, 3, 4]
    for aᵣ in [0.1, 0.2, 0.3, 0.4, 0.5], r0 in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]
        net.layers[:refuge].intensity = r0
        aᵣ_matrix = sparse([0 0 0 0; 0 0 0 0; aᵣ 0 0 0; aᵣ aᵣ aᵣ 0])
        aᵣ31 = aᵣ / (1 + 2 * r0)
        aᵣ41 = aᵣ / (1 + 2 * r0)
        aᵣ42 = aᵣ / (1 + 1 * r0)
        aᵣ43 = aᵣ / (1 + 1 * r0 + 2 * r0)
        aᵣ_refuge_matrix = sparse([0 0 0 0; 0 0 0 0; aᵣ31 0 0 0; aᵣ41 aᵣ42 aᵣ43 0])
        @test Internals.effect_refuge(aᵣ_matrix, B, net) == aᵣ_refuge_matrix
    end
end
