# Set or generate attack rates for every trophic link in the model.

# Mostly duplicated from handling times.

# (reassure JuliaLS)
(false) && (local AttackRate, _AttackRate)

# ==========================================================================================
module AttackRate_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Foodweb, _Foodweb, BodyMass, MetabolicClass, _Temperature

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    a_r::SparseMatrix{Float64}
    foodweb::Brought(Foodweb)
    Raw(a_r, foodweb = _Foodweb) = new(@tographdata(a_r, SparseMatrix{Float64}), foodweb)
end
F.implied_blueprint_for(bp::Raw, ::_Foodweb) = Foodweb(bp.a_r .!= 0)
@blueprint Raw "sparse matrix"
export Raw

F.early_check(bp::Raw) = check_edges(check, bp.a_r)
check(a_r, ref = nothing) = check_value(>=(0), a_r, ref, :a_r, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; a_r) = bp
    A = @ref raw.trophic.matrix
    @check_template a_r A "trophic links"
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.a_r)

# Stored only in scratch space: only used within adequate functional response.
expand!(raw, a_r) = raw._scratch[:attack_rate] = a_r

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    a_r::Float64
end
@blueprint Flat "uniform attack rate" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.a_r)
function F.expand!(raw, bp::Flat)
    (; a_r) = bp
    A = @ref raw.trophic.matrix
    a_r = to_template(a_r, A)
    expand!(raw, a_r)
end

#-------------------------------------------------------------------------------------------
mutable struct Adjacency <: Blueprint
    a_r::@GraphData Adjacency{Float64}
    foodweb::Brought(Foodweb)
    Adjacency(a_r, foodweb = _Foodweb) = new(@tographdata(a_r, Adjacency{Float64}), foodweb)
end
function F.implied_blueprint_for(bp::Adjacency, ::_Foodweb)
    (; a_r) = bp
    Foodweb(@tographdata a_r Adjacency{:bin})
end
@blueprint Adjacency "[predactor => [prey => attack rate]] adjacency list"
export Adjacency

F.early_check(bp::Adjacency) = check_edges(check, bp.a_r)
function F.late_check(raw, bp::Adjacency)
    (; a_r) = bp
    index = @ref raw.species.index
    A = @ref raw.trophic.matrix
    @check_list_refs a_r "trophic link" index template(A)
end

function F.expand!(raw, bp::Adjacency)
    index = @ref raw.species.index
    a_r = to_sparse_matrix(bp.a_r, index, index)
    expand!(raw, a_r)
end

#-------------------------------------------------------------------------------------------
# With Miele2019 formulae.
mutable struct Miele2019 <: Blueprint end
@blueprint Miele2019 "body masses" depends(BodyMass)
export Miele2019
function F.expand!(raw, ::Miele2019)
    a_r = Internals.attack_rate(raw._foodweb)
    expand!(raw, a_r)
end

#-------------------------------------------------------------------------------------------
binzer2016_allometry_rates() = (
    E_a = -0.38,
    allometry = Allometry(;
        producer = (a = 0, b = 0.25, c = -0.8), # ? Is that intended @hanamayall?
        invertebrate = (a = exp(-13.1), b = 0.25, c = -0.8),
        ectotherm = (a = exp(-13.1), b = 0.25, c = -0.8),
    ),
)

mutable struct Temperature <: Blueprint
    E_a::Float64
    allometry::Allometry
    Temperature(E_a; kwargs...) = new(E_a, parse_allometry_arguments(kwargs))
    Temperature(E_a, allometry::Allometry) = new(E_a, allometry)
    function Temperature(default::Symbol)
        @check_symbol default (:Binzer2016,)
        @expand_symbol default (:Binzer2016 => new(binzer2016_allometry_rates()...))
    end
end
@blueprint Temperature "allometric rates and activation energy" depends(
    _Temperature,
    BodyMass,
    MetabolicClass,
)
export Temperature

function F.early_check(bp::Temperature)
    (; allometry) = bp
    check_template(
        allometry,
        binzer2016_allometry_rates()[2],
        "attack_rate (from temperature)",
    )
end

function F.expand!(raw, bp::Temperature)
    (; E_a) = bp
    T = @get raw.T
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    A = @ref raw.trophic.matrix
    a_r = sparse_edges_allometry(bp.allometry, A, M, mc; E_a, T)
    expand!(raw, a_r)
end

end

# ==========================================================================================
@component AttackRate{Internal} requires(Foodweb) blueprints(AttackRate_)
export AttackRate

function (::_AttackRate)(a_r)

    a_r = @tographdata a_r {Symbol, Scalar, SparseMatrix, Adjacency}{Float64}
    @check_if_symbol a_r (:Miele2019, :Binzer2016)

    if a_r isa Symbol
        @expand_symbol(
            a_r,
            :Miele2019 => AttackRate.Miele2019(),
            :Binzer2016 => AttackRate.Temperature(a_r),
        )
    elseif a_r isa Real
        AttackRate.Flat(a_r)
    elseif a_r isa AbstractMatrix
        AttackRate.Raw(a_r)
    else
        AttackRate.Adjacency(a_r)
    end

end

@expose_data edges begin
    property(attack_rate)
    depends(AttackRate)
    @species_index
    ref(raw -> raw._scratch[:attack_rate])
    get(AttackRates{Float64}, sparse, "trophic link")
    template(raw -> @ref raw.trophic.matrix)
    write!((raw, rhs::Real, i, j) -> AttackRate_.check(rhs, (i, j)))
end

function F.shortline(io::IO, model::Model, ::_AttackRate)
    print(io, "Attack rate: ")
    showrange(io, model._attack_rate)
end
