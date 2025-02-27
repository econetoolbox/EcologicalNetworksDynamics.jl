# Set or generate handling times for every trophic link in the model.

# Mostly duplicated from Efficiency.

# (reassure JuliaLS)
(false) && (local HandlingTime, _HandlingTime)

# ==========================================================================================
module HandlingTime_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Foodweb, _Foodweb, BodyMass, MetabolicClass, _Temperature

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    h_t::SparseMatrix{Float64}
    foodweb::Brought(Foodweb)
    Raw(h_t, foodweb = _Foodweb) = new(@tographdata(h_t, SparseMatrix{Float64}), foodweb)
end
F.implied_blueprint_for(bp::Raw, ::_Foodweb) = Foodweb(bp.h_t .!= 0)
@blueprint Raw "sparse matrix"
export Raw

F.early_check(bp::Raw) = check_edges(check, bp.h_t)
check(h_t, ref = nothing) = check_value(>=(0), h_t, ref, :h_t, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; h_t) = bp
    A = @ref raw.trophic.matrix
    @check_template h_t A "trophic links"
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.h_t)

# Stored only in scratch space: only used within adequate functional response.
expand!(raw, h_t) = raw._scratch[:handling_time] = h_t

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    h_t::Float64
end
@blueprint Flat "uniform handling time" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.h_t)
function F.expand!(raw, bp::Flat)
    (; h_t) = bp
    A = @ref raw.trophic.matrix
    h_t = to_template(h_t, A)
    expand!(raw, h_t)
end

#-------------------------------------------------------------------------------------------
mutable struct Adjacency <: Blueprint
    h_t::@GraphData Adjacency{Float64}
    foodweb::Brought(Foodweb)
    Adjacency(h_t, foodweb = _Foodweb) = new(@tographdata(h_t, Adjacency{Float64}), foodweb)
end
function F.implied_blueprint_for(bp::Adjacency, ::_Foodweb)
    (; h_t) = bp
    Foodweb(@tographdata h_t Adjacency{:bin})
end
@blueprint Adjacency "[predactor => [prey => handling time]] adjacency list"
export Adjacency

F.early_check(bp::Adjacency) = check_edges(check, bp.h_t)
function F.late_check(raw, bp::Adjacency)
    (; h_t) = bp
    index = @ref raw.species.index
    A = @ref raw.trophic.matrix
    @check_list_refs h_t "trophic link" index template(A)
end

function F.expand!(raw, bp::Adjacency)
    index = @ref raw.species.index
    h_t = to_sparse_matrix(bp.h_t, index, index)
    expand!(raw, h_t)
end

#-------------------------------------------------------------------------------------------
# With Miele2019 formulae.
mutable struct Miele2019 <: Blueprint end
@blueprint Miele2019 "body masses" depends(BodyMass)
export Miele2019
function F.expand!(raw, ::Miele2019)
    h_t = Internals.handling_time(raw._foodweb)
    expand!(raw, h_t)
end

#-------------------------------------------------------------------------------------------
binzer2016_allometry_rates() = (
    E_a = 0.26,
    allometry = Allometry(;
        producer = (a = 0, b = -0.45, c = 0.47), # ? Is that intended @hanamayall?
        invertebrate = (a = exp(9.66), b = -0.45, c = 0.47),
        ectotherm = (a = exp(9.66), b = -0.45, c = 0.47),
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
        "handling time (from temperature)",
    )
end

function F.expand!(raw, bp::Temperature)
    (; E_a) = bp
    T = @get raw.T
    M = @ref raw.M
    mc = @ref raw.metabolic_class
    A = @ref raw.trophic.matrix
    h_t = sparse_edges_allometry(bp.allometry, A, M, mc; E_a, T)
    expand!(raw, h_t)
end

end

# ==========================================================================================
@component HandlingTime{Internal} requires(Foodweb) blueprints(HandlingTime_)
export HandlingTime

function (::_HandlingTime)(h_t)

    h_t = @tographdata h_t {Symbol, Scalar, SparseMatrix, Adjacency}{Float64}
    @check_if_symbol h_t (:Miele2019, :Binzer2016)

    if h_t isa Symbol
        @expand_symbol(
            h_t,
            :Miele2019 => HandlingTime.Miele2019(),
            :Binzer2016 => HandlingTime.Temperature(h_t),
        )
    elseif h_t isa Real
        HandlingTime.Flat(h_t)
    elseif h_t isa AbstractMatrix
        HandlingTime.Raw(h_t)
    else
        HandlingTime.Adjacency(h_t)
    end

end

@expose_data edges begin
    property(handling_time)
    depends(HandlingTime)
    @species_index
    ref(raw -> raw._scratch[:handling_time])
    get(HandlingTimes{Float64}, sparse, "trophic link")
    template(raw -> @ref raw.trophic.matrix)
    write!((raw, rhs::Real, i, j) -> HandlingTime_.check(rhs, (i, j)))
end

function F.shortline(io::IO, model::Model, ::_HandlingTime)
    print(io, "Handling time: ")
    showrange(io, model._handling_time)
end
