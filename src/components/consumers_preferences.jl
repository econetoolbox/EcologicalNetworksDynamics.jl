# Set or generate consumers preferences for every trophic link in the model.

# Mostly duplicated from Efficiency.

# (reassure JuliaLS)
(false) && (local ConsumersPreferences, _ConsumersPreferences)

# ==========================================================================================
module ConsumersPreferences_
include("blueprint_modules.jl")
include("blueprint_modules_identifiers.jl")
import .EN: Foodweb, _Foodweb

#-------------------------------------------------------------------------------------------
mutable struct Raw <: Blueprint
    w::SparseMatrix{Float64}
    foodweb::Brought(Foodweb)
    Raw(w, foodweb = _Foodweb) = new(@tographdata(w, SparseMatrix{Float64}), foodweb)
end
F.implied_blueprint_for(bp::Raw, ::_Foodweb) = Foodweb(bp.w .!= 0)
@blueprint Raw "sparse matrix"
export Raw

F.early_check(bp::Raw) = check_edges(check, bp.w)
check(w, ref = nothing) = check_value(>=(0), w, ref, :w, "Not a positive value")

function F.late_check(raw, bp::Raw)
    (; w) = bp
    A = @ref raw.trophic.matrix
    @check_template w A "trophic links"
end

F.expand!(raw, bp::Raw) = expand!(raw, bp.w)
expand!(raw, w) = raw._scratch[:consumers_preferences] = w

#-------------------------------------------------------------------------------------------
mutable struct Flat <: Blueprint
    w::Float64
end
@blueprint Flat "uniform consumer preferences" depends(Foodweb)
export Flat

F.early_check(bp::Flat) = check(bp.w)
function F.expand!(raw, bp::Flat)
    (; w) = bp
    A = @ref raw.trophic.matrix
    w = to_template(w, A)
    expand!(raw, w)
end

#-------------------------------------------------------------------------------------------
mutable struct Adjacency <: Blueprint
    w::@GraphData Adjacency{Float64}
    foodweb::Brought(Foodweb)
    Adjacency(w, foodweb = _Foodweb) = new(@tographdata(w, Adjacency{Float64}), foodweb)
end
function F.implied_blueprint_for(bp::Adjacency, ::_Foodweb)
    (; w) = bp
    Foodweb(@tographdata w Adjacency{:bin})
end
@blueprint Adjacency "[predactor => [prey => preference]] adjacency list"
export Adjacency

F.early_check(bp::Adjacency) = check_edges(check, bp.w)
function F.late_check(raw, bp::Adjacency)
    (; w) = bp
    index = @ref raw.species.index
    A = @ref raw.trophic.matrix
    @check_list_refs w "trophic link" index template(A)
end

function F.expand!(raw, bp::Adjacency)
    index = @ref raw.species.index
    w = to_sparse_matrix(bp.w, index, index)
    expand!(raw, w)
end

#-------------------------------------------------------------------------------------------
# Homogeneous preferences (automatically calculated).
struct Homogeneous <: Blueprint end
@blueprint Homogeneous "homogeneous preferences"
export Homogeneous

function F.expand!(raw, ::Homogeneous)
    w = Internals.homogeneous_preference(raw._foodweb)
    expand!(raw, w)
end

end

# ==========================================================================================
@component begin
    ConsumersPreferences{Internal}
    requires(Foodweb)
    blueprints(ConsumersPreferences_)
end
export ConsumersPreferences

(::_ConsumersPreferences)() = ConsumersPreferences.Homogeneous()

function (::_ConsumersPreferences)(w)

    w = @tographdata w {Symbol, Scalar, SparseMatrix, Adjacency}{Float64}

    if w isa Symbol
        @check_symbol w :homogeneous
        @expand_symbol(w, :homogeneous => ConsumersPreferences.Homogeneous())
    elseif w isa SparseMatrix
        ConsumersPreferences.Raw(w)
    elseif w isa Real
        ConsumersPreferences.Flat(w)
    else
        ConsumersPreferences.Adjacency(w)
    end

end

@expose_data edges begin
    property(consumers.preferences, w)
    depends(ConsumersPreferences)
    @species_index
    ref(raw -> raw._scratch[:consumers_preferences])
    get(ConsumersPreferencesWeights{Float64}, sparse, "trophic link")
    template(raw -> @ref raw.trophic.matrix)
    write!((raw, rhs::Real, i, j) -> begin
        ConsumersPreferences_.check(rhs, (i, j))
    end)
end

# Just display range.
function F.shortline(io::IO, model::Model, ::_ConsumersPreferences)
    print(io, "Consumer preferences: ")
    showrange(io, model.consumers._preferences)
end
