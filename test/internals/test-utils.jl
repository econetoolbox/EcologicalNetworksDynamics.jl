module TestUtils
using Test
using EcologicalNetworksDynamics.Internals
using Main.TestInternals

#### Set up food webs for tests ####
foodweb_2links = FoodWeb([0 0 0 0; 0 0 0 0; 1 0 0 0; 0 1 0 0]; quiet = true)
foodweb_3links = FoodWeb([0 0 0 0; 0 0 0 0; 1 1 0 0; 0 0 1 0])
foodweb_5links = FoodWeb([0 0 0 0; 1 0 0 0; 1 1 1 0; 0 0 1 0]; quiet = true)
foodweb_2links.metabolic_class =
    ["producer", "producer", "invertebrate", "ectotherm vertebrate"]
#### end ####

@testset "Identify metabolic classes, producers, preys and predators" begin
    # Function called on one species of the network (return a boolean)
    @test Internals.isinvertebrate(1, foodweb_2links) == false
    @test Internals.isinvertebrate(2, foodweb_2links) == false
    @test Internals.isinvertebrate(3, foodweb_2links) == true
    @test Internals.isinvertebrate(4, foodweb_2links) == false

    @test Internals.isvertebrate(1, foodweb_2links) == false
    @test Internals.isvertebrate(2, foodweb_2links) == false
    @test Internals.isvertebrate(3, foodweb_2links) == false
    @test Internals.isvertebrate(4, foodweb_2links) == true

    @test Internals.isproducer(1, foodweb_2links) == true
    @test Internals.isproducer(2, foodweb_2links) == true
    @test Internals.isproducer(3, foodweb_2links) == false
    @test Internals.isproducer(4, foodweb_2links) == false

    @test Internals.ispredator(1, foodweb_2links) == false
    @test Internals.ispredator(2, foodweb_2links) == false
    @test Internals.ispredator(3, foodweb_2links) == true
    @test Internals.ispredator(4, foodweb_2links) == true

    @test Internals.isprey(1, foodweb_2links) == true
    @test Internals.isprey(2, foodweb_2links) == true
    @test Internals.isprey(3, foodweb_2links) == false
    @test Internals.isprey(4, foodweb_2links) == false

    # Functions called on the whole network (return a vector of indexes)
    @test Internals.invertebrates(foodweb_2links) == [3]
    @test Internals.invertebrates(foodweb_2links) == [3]
    @test Internals.invertebrates(foodweb_2links) == [3]

    @test Internals.vertebrates(foodweb_2links) == [4]
    @test Internals.vertebrates(foodweb_2links) == [4]
    @test Internals.vertebrates(foodweb_2links) == [4]

    @test Internals.producers(foodweb_2links) == [1, 2]
    @test Internals.producers(foodweb_3links) == [1, 2]
    @test Internals.producers(foodweb_5links) == [1]
    @test Internals.producers(foodweb_2links.A) == [1, 2]
    @test Internals.producers(foodweb_3links.A) == [1, 2]
    @test Internals.producers(foodweb_5links.A) == [1]

    @test Internals.predators(foodweb_2links) == [3, 4]
    @test Internals.predators(foodweb_3links) == [3, 4]
    @test Internals.predators(foodweb_5links) == [2, 3, 4]

    @test Internals.preys(foodweb_2links) == [1, 2]
    @test Internals.preys(foodweb_3links) == [1, 2, 3]
    @test Internals.preys(foodweb_5links) == [1, 2, 3]

    @test trophic_levels(foodweb_2links) == [1.0, 1.0, 2.0, 2.0]
    @test trophic_levels(foodweb_3links) == [1.0, 1.0, 2.0, 3.0]
    @test trophic_levels([0 1 0; 0 0 0; 1 0 0]) == [2.0, 1.0, 3.0]
end

@testset "Find predators and preys of a given species" begin
    @test Internals.preys_of(1, foodweb_5links) == []
    @test Internals.preys_of(2, foodweb_5links) == [1]
    @test Internals.preys_of(3, foodweb_5links) == [1, 2, 3]
    @test Internals.preys_of(4, foodweb_5links) == [3]

    @test Internals.predators_of(1, foodweb_5links) == [2, 3]
    @test Internals.predators_of(2, foodweb_5links) == [3]
    @test Internals.predators_of(3, foodweb_5links) == [3, 4]
    @test Internals.predators_of(4, foodweb_5links) == []
end

@testset "Find predators sharing at least one prey" begin
    @test Internals.share_prey(1, 2, foodweb_5links) == false
    @test Internals.share_prey(2, 1, foodweb_5links) == false
    @test Internals.share_prey(3, 2, foodweb_5links) == true
    @test Internals.share_prey(2, 3, foodweb_5links) == true
    @test Internals.share_prey(2, 4, foodweb_5links) == false
    @test Internals.share_prey(4, 2, foodweb_5links) == false
    @test Internals.share_prey(3, 4, foodweb_5links) == true
    @test Internals.share_prey(4, 3, foodweb_5links) == true
end

@testset "Find number of resources of each species." begin
    @test Internals.number_of_resource(foodweb_2links) == [0, 0, 1, 1]
    @test Internals.number_of_resource(foodweb_3links) == [0, 0, 2, 1]
    @test Internals.number_of_resource(foodweb_5links) == [0, 1, 3, 1]
end

end
