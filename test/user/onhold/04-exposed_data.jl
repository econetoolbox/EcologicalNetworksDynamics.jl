# Cover @exposed_data macro results via existing components.
module TestExposedData

using EcologicalNetworksDynamics
using SparseArrays
using Test

Value = EcologicalNetworksDynamics.Internal # To make @sysfails work.
import ..Main: @viewfails, @sysfails, @argfails

const EN = EcologicalNetworksDynamics

# ==========================================================================================
@testset "Foodweb as a typical example of exposed data." begin

    SN = EN.SpeciesNames
    PM = EN.ProducersMask
    HM = EN.HerbivoryMatrix

    m = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # Nodes view.

    # Access with either indices or labels.
    @test m.producers.mask[3]
    @test m.producers.mask[:c]
    @test m.producers.mask['c']
    @test m.producers.mask["c"]

    # Access ranges, masks, etc.
    @test m.producers.mask[2:3] == Bool[0, 1]
    @test m.producers.mask[Bool[1, 0, 1]] == Bool[0, 1]
    @test m.producers.mask[2:end] == Bool[0, 1]
    @test m.producers.mask[2:end-1] == Bool[0]

    # Invalid index.
    @viewfails(
        m.producers.mask[5],
        PM,
        "Species index [5] is off-bounds for a view into 3 nodes data."
    )

    # Invalid label.
    @viewfails(
        m.producers.mask['x'],
        PM,
        "Invalid species node label. \
         Expected either :a, :b or :c, got instead: 'x'."
    )

    # Label access into a view without an index.
    @viewfails(m.species.names[:a], SN, "No index to interpret species node label :a.")

    # Forbid mutation.
    @viewfails(
        m.producers.mask[1] = true,
        PM,
        "This view into graph nodes data is read-only."
    )
    @viewfails(
        m.producers.mask[1:2] = true,
        PM,
        "This view into graph nodes data is read-only."
    )

    @sysfails(
        m.producers.mask = Bool[1, 1, 1],
        Property(producers.mask, "This property is read-only.")
    )

    # Same with edges.

    #---------------------------------------------------------------------------------------
    # Edges view.

    @test m.trophic.herbivory_matrix[2, 3] == true
    @test m.trophic.herbivory_matrix[:b, :c] == true
    @test m.trophic.herbivory_matrix[1:2, 2:3] == [
        0 1
        0 1
    ]

    @viewfails(
        m.trophic.herbivory_matrix[5, 8],
        HM,
        "Herbivorous link index [5, 8] is off-bounds \
         for a view into (3, 3) edges data."
    )

    @viewfails(
        m.trophic.herbivory_matrix[:x, :b],
        HM,
        "Invalid herbivorous link edge source label: :x. \
         Expected either :a, :b or :c, got instead: :x."
    )

    @viewfails(
        m.trophic.herbivory_matrix[:a, :x],
        HM,
        "Invalid herbivorous link edge target label: :x. \
         Expected either :a, :b or :c, got instead: :x."
    )

    # Can't mix styles.
    @argfails(m.trophic.herbivory_matrix[:x, 8], "invalid index: :x of type Symbol")

    @viewfails(
        m.trophic.herbivory_matrix[1, 2] = true,
        HM,
        "This view into graph edges data is read-only."
    )
    @viewfails(
        m.trophic.herbivory_matrix[1:2, 2:3] = true,
        HM,
        "This view into graph edges data is read-only."
    )

    @sysfails(
        m.trophic.herbivory_matrix = Bool[0 1; 0 1],
        Property(trophic.herbivory_matrix, "This property is read-only.")
    )

end

@testset "Hill exponent as a typical example of mutable exposed graph data." begin

    m = Model(HillExponent(5))

    # Read.
    @test m.hill_exponent == 5

    # Write.
    m.hill_exponent = 8
    @test m.hill_exponent == 8
    # Conversion happened.
    @test m.hill_exponent isa Float64

    # Type-guard.
    @sysfails(
        m.hill_exponent = "string",
        Property(hill_exponent, "Cannot set with a value of type String: \"string\".")
    )
    @sysfails(
        m.hill_exponent = [],
        Property(hill_exponent, "Cannot set with a value of type Vector{Any}: Any[].")
    )

end

@testset "Growth as a typical example of mutable exposed sparse node data." begin

    GR = EN.GrowthRates

    m = Model(Foodweb([:a => [:b, :c], :b => [:c, :d]]), GrowthRate([0, 0, 1, 1]))

    # Allow single-value write.
    @test m.r == [0, 0, 1, 1]
    m.r[3] = 2
    @test m.r == [0, 0, 2, 1]
    @test m.growth_rate == [0, 0, 2, 1] # (no matter the alias)

    m.r[:c] = 3
    @test m.r == m.growth_rate == [0, 0, 3, 1]

    # Allow range-writes, feeling like a regular array.
    m.r[3:4] .= 4
    @test m.r == m.growth_rate == [0, 0, 4, 4]
    m.r[3:4] = [5, 6]
    @test m.r == m.growth_rate == [0, 0, 5, 6]

    # Lock the lid of the following pandora box.
    @sysfails(m.r = [0, 0, 7, 8], Property(r, "This property is read-only."))
    # (allowing the above would easily lead to leaking references or invalidating views)

    # But here one correct way to replace the whole data in-place.
    m.r[m.producers.mask] = [9, 10]
    @test m.r == m.growth_rate == [0, 0, 9, 10]

    # So that aliasing views work as expected:
    r = m.r
    @test r == [0, 0, 9, 10]
    m.r[3:4] = [11, 12]
    @test r == [0, 0, 11, 12]

    # Disallow meaningless writes outside the template.
    @viewfails(
        m.r[2] = 1,
        GR,
        "Invalid producer index [2] to write node data. \
         Valid indices for this template are 3 and 4."
    )

    @viewfails(
        m.r[:b] = 1,
        GR,
        "Invalid producer label [:b] ([2]) to write node data. \
         Valid labels for this template are :c and :d."
    )

    @viewfails(
        m.r[2:3] .= 1,
        GR,
        "Invalid producer index [2] to write node data. \
         Valid indices for this template are 3 and 4."
    )

end

@testset "Mortality as a typical example of mutable exposed dense node data." begin

    m = Model(Foodweb([:a => [:b, :c], :b => [:c, :d]]), Mortality(0))

    @test m.d == [0, 0, 0, 0]

    # Lock the pandora lid.
    @sysfails(m.d = [1, 2, 3, 4], Property(d, "This property is read-only."))

    # But replacing the whole data inplace is possible.
    m.d .= [5, 6, 7, 8]
    @test m.d == [5, 6, 7, 8]

end

@testset "Efficiency as a typical example of mutable exposed edge data." begin

    EF = EN.EfficiencyRates
    m = Model(
        Foodweb([:a => [:b, :c], :b => [:c, :d]]),
        Efficiency(:Miele2019; e_herbivorous = 0.1, e_carnivorous = 0.2),
    )

    @test m.efficiency == m.e == [
        0 2 1 0
        0 0 1 1
        0 0 0 0
        0 0 0 0
    ] ./ 10

    # Allow single-value write.
    m.e[2, 3] = 0.3
    @test m.efficiency == m.e == [
        0 2 1 0
        0 0 3 1
        0 0 0 0
        0 0 0 0
    ] ./ 10

    m.e[:b, :d] = 0.4
    @test m.e == [
        0 2 1 0
        0 0 3 4
        0 0 0 0
        0 0 0 0
    ] ./ 10

    # Disallow linear accesses.
    @viewfails(
        m.e[5],
        EF,
        "Edges data are 2-dimensional: \
         cannot access trophic link data values with 1 index: [5]."
    )

    # Allow range-writes, feeling like a regular matrix.
    m.e[1:2, 3] .= 0.6
    @test m.e == [
        0 2 6 0
        0 0 6 4
        0 0 0 0
        0 0 0 0
    ] ./ 10

    m.e[1:2, 3] = [0.8, 0.9]
    @test m.e == [
        0 2 8 0
        0 0 9 4
        0 0 0 0
        0 0 0 0
    ] ./ 10

    # Lock the lid of the following pandora box.
    @sysfails(m.e = [0 0; 1 1], Property(e, "This property is read-only."))
    # (allowing the above would easily lead to leaking references or invalidating views)

    # But here one correct way to replace the whole data.
    m.e[m.A] = [0.1, 0.2, 0.3, 0.4]
    @test m.e == [
        0 1 2 0
        0 0 3 4
        0 0 0 0
        0 0 0 0
    ] ./ 10

    # So that aliasing views work as expected:
    e = m.efficiency
    @test e == [
        0 1 2 0
        0 0 3 4
        0 0 0 0
        0 0 0 0
    ] ./ 10
    m.e[1:2, 3] = [0.5, 0.6]
    @test e == [
        0 1 5 0
        0 0 6 4
        0 0 0 0
        0 0 0 0
    ] ./ 10

    # Disallow meaningless writes outside the template.
    @viewfails(
        m.e[:b, :a] = 1,
        EF,
        "Invalid trophic link labels [:b, :a] ([2, 1]) to write edge data. \
         Valid indices must comply to the following template:\n\
         4×4 $SparseMatrixCSC{Bool, Int64} with 4 stored entries:\n \
          ⋅  1  1  ⋅\n \
          ⋅  ⋅  1  1\n \
          ⋅  ⋅  ⋅  ⋅\n \
          ⋅  ⋅  ⋅  ⋅"
    )
    @viewfails(
        m.e[2:3, 2:4] .= 1,
        EF,
        "Invalid trophic link index [2, 2] to write edge data. \
         Valid indices must comply to the following template:\n\
         4×4 $SparseMatrixCSC{Bool, Int64} with 4 stored entries:\n \
          ⋅  1  1  ⋅\n \
          ⋅  ⋅  1  1\n \
          ⋅  ⋅  ⋅  ⋅\n \
          ⋅  ⋅  ⋅  ⋅"
    )

end

@testset "Nutrients concentration as non-squared edge data + dense template indexes." begin

    CN = EN.Nutrients.Concentrations
    m = Model(Foodweb([:a => [:b, :c]]), Nutrients.Nodes([:u, :v, :w]))
    m += Nutrients.Concentration([
        1 2 3
        4 5 6
    ])

    # Watch the semantics here: 2 is not the "2nd species", but the "2nd producer".
    c = m.nutrients.concentration
    c[2, 3] = 7
    @test m.nutrients.concentration == c == [
        1 2 3
        4 5 7
    ]

    # And :b is the "1st producer".
    c[:b, :v] = 8
    @test m.nutrients.concentration == c == [
        1 8 3
        4 5 7
    ]

    # Guard against meaningless accesses outside the references spaces.
    @viewfails(
        c[3, 1],
        CN,
        "Producer-to-nutrient link index [3, 1] is off-bounds \
         for a view into (2, 3) edges data."
    )

    @viewfails(
        c[:x, :u],
        CN,
        "Invalid producer-to-nutrient link edge source label: :x. \
         Expected either :b or :c, got instead: :x."
    )

    @viewfails(
        c[:b, :x],
        CN,
        "Invalid producer-to-nutrient link edge target label: :x. \
         Expected either :u, :v or :w, got instead: :x."
    )

end

end
