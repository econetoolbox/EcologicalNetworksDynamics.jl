# Generate typical component bringing a new class.

"""
Expand into a new nodes class.
"""
abstract type ClassBlueprint <: Blueprint end

"""
From raw nodes names.
"""
abstract type ClassNames <: ClassBlueprint end

"""
From a number of nodes.
"""
abstract type ClassNumber <: ClassBlueprint end

"""
Typical setup for a component bringing a new class to the network.
"""
function define_class_component(mod::Module, d::D.Class)
    short_prefix, singular, plural, Singular, Plural = D.name_variants(d)
    Plural_ = Symbol(Plural, :_) # Blueprints module name.
    _Plural = Symbol(:_, Plural) # Component type name.
    s, S, short_prefix = Meta.quot.((plural, Plural, short_prefix)) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    bpmod = mod.eval(
        (
            quote
                module $Plural_
                import EcologicalNetworksDynamics.NetworkFramework:
                    F, NF, D, Model, @bp_construct
                const d = $d
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    bpmod.eval(quote
        mutable struct Names <: NF.ClassNames
            names::Vector{Symbol}
            @bp_construct(Names)
        end
        export Names
        $NF.register_blueprint(Names, "raw $($s) names"; d)
    end)

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    bpmod.eval(quote
        mutable struct Number <: NF.ClassNumber
            n::Int
            @bp_construct(Number)
        end
        export Number
        $NF.register_blueprint(Number, "number of $($s)"; d)
    end)

    # ======================================================================================
    # The component itself and generic blueprints constructors.
    comp = NF.eval(
        quote # Need to reach toplevel first to access generated values.
            define_component($(Meta.quot(Plural)), $mod; blueprints = [$bpmod])
        end,
    )
    C = typeof(comp)

    # Dispatch to correct constructor depending on input given to direct call on component.
    DT = typeof(d)
    NF.eval(quote
        D.component(::$DT) = $comp
        (::$C)(n::Integer) = $comp.Number(n)
        (::$C)(names...) = $comp.Names(names...)
    end)

    # Display.
    NF.eval(quote
        F.shortline(io::IO, model::Model, ::$C) = class_shortline($d, io, model)
    end)

    define_class_properties(mod, d; depends = [C])
    comp
end

# ==========================================================================================

function define_class_properties(mod::Module, d::D.Class; depends = [])
    short_prefix, singular, plural, Singular, Plural = D.name_variants(d)

    NF.define_propspace(plural)
    defmeth(fn, s) = NF.define_method(fn; depends, read_as = [:($plural.$s)])

    # Wrap all within a separate module
    # or identical definitions end up being considered the same functions.
    # https://julialang.zulipchat.com/#narrow/channel/137791-general/topic/Identity.20of.20local.20functions.2E/with/590238482
    M = Symbol(Plural, :Methods)
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics.NetworkFramework: N, V, D, Network, Model
                using OrderedCollections
                const defmeth = $defmeth
                const d = $d
                const c = D.class(d)

                # Ordered index.
                ref_index(n::Network) = N.class(n, c).index
                get_index(n::Network) = deepcopy(ref_index(n).forward)
                indices(n::Network) = N.node_indices(n, c)

                # Nodes counts and nodes labels.
                # The 'ref' variant is more efficient but unexposed.
                get_number(n::Network) = N.n_nodes(n, c)
                ref_names(n::Network) = ref_index(n).reverse
                get_names(::Network, m::Model) = V.names_view(d, m)

                # Mask within parent class.
                get_parent_index(n::Network) =
                    OrderedDict(l => i for (l, i) in zip(ref_names(n), indices(n)))
                mask(n::Network, m::Model) =
                    V.mask_view(D.Subclass(c, N.class(n, c).parent), m)

                defmeth(get_number, :number)
                defmeth(ref_names, :_names)
                defmeth(get_names, :names)
                defmeth(ref_index, :_index)
                defmeth(get_index, :index)
                defmeth(indices, :indices)
                defmeth(get_parent_index, :parent_index)
                defmeth(mask, :mask)
                end
            end
        ).args |> last,
    )
end

# ==========================================================================================
# Specialisation for this typical component type.

datatype(::Type{<:ClassNames}) = Vector{Symbol}
datatype(::Type{<:ClassNumber}) = Int
data(b::ClassNames) = b.names
data(b::ClassNumber) = b.n

# Construct: allow passing names as separate arguments.
construct(BP::Type{<:ClassNames}, first, second, rest...) =
    @invoke construct(BP::Type{<:Blueprint}, (first, second, rest...))

#-------------------------------------------------------------------------------------------
# Intrinsic check.

# Names: forbid duplicates (triangular check).
function intrinsic_check(B::Type{<:ClassNames}, names::Vector{Symbol})
    already = OrderedDict{Symbol,Int}() # {name: index}
    for (i, name) in enumerate(names)
        if haskey(already, name)
            Class = B |> dispatcher |> D.CamelCaseSingular
            j = already[name]
            checkerr(i, name, "$Class $j and $i would both be named $(repr(name)).")
        end
        already[name] = i
    end
    names
end

# Number: forbid negative number of nodes.
function intrinsic_check(B::Type{<:ClassNumber}, n::Int)
    n >= 0 && return n
    class = B |> dispatcher |> D.snake_case_plural
    checkerr(n, "Cannot construct a negative number of $class nodes.")
end

#-------------------------------------------------------------------------------------------
# Expand.

# From names.
function expand!(m::Model, d::D.Class, names)
    class = d |> D.class
    network = NF.network(m)
    N.add_class!(network, class, names)
end

# From number (generate names).
function expand!(m::Model, b::ClassNumber, n)
    d = dispatcher(b)
    prefix = D.short_prefix(d)
    names = (Symbol(prefix, i) for i in 1:n)
    expand!(m, d, names)
end

#-------------------------------------------------------------------------------------------
# Display.

function class_shortline(d::D.Class, io::IO, m::Model)
    class = D.snake_case_plural(d)
    Class = D.CamelCaseSingular(d)
    names = getproperty(m, class)._names
    n = length(names)
    print(io, "$Class: $n ($(EN.join_elided(names, ", ")))")
end
