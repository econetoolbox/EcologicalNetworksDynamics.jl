# Subtype blueprint to specialize extension points over typical ones.
"""
Expand into a new nodes class from raw nodes names.
"""
abstract type ClassNamesBlueprint <: Blueprint end

"""
Expand into a new nodes class from a number of nodes.
"""
abstract type ClassNumberBlueprint <: Blueprint end

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
    bpmod = mod.eval((
        quote
            module $Plural_
            import EcologicalNetworksDynamics: F, NF, Model
            const d = $d
            end
        end
    ).args |> last)

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    bpmod.eval(
        quote
            mutable struct Names <: NF.ClassNamesBlueprint
                names::Vector{Symbol}
                Names(names...) = new(NF.construct(d, Names, names...))
            end

            # Declare as a blueprint.
            NF.define_blueprint(Names, "raw $($s) names")

            # Export so it gets picked by `NF.define_component` when passing `bpmod` later.
            export Names

            # Verify intrinsic blueprint values.
            F.early_check(bp::Names) = NF.early_check(d, bp)

            # Verify against model, using the data passed by early_check.
            F.late_check(m::Model, bp::Names, early_data) =
                NF.late_check(d, m, bp, early_data)

            # Expand into a new compartment, using the data passed by late_check.
            F.expand!(m::Model, bp::Names, late_data) = NF.expand!(d, m, bp, late_data)

        end,
    )

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    bpmod.eval(
        quote
            mutable struct Number <: NF.ClassNumberBlueprint
                n::Int
                Number(input) = new(NF.construct(d, Number, input))
            end
            export Number
            NF.define_blueprint(Number, "number of $($s)")
            F.early_check(bp::Number) = NF.early_check(d, bp)
            F.late_check(bp::Number, m::Model, data) = NF.early_check(d, m, bp, data)
            F.expand!(m::Model, bp::Number, data) = NF.expand!(d, m, bp, data)
        end,
    )

    # ======================================================================================
    # The component itself and generic blueprints constructors.
    comp = mod.eval(
        quote # Need to reach toplevel first to access generated values.
            $NF.define_component($(Meta.quot(Plural)), $mod; blueprints = [$bpmod])
        end,
    )
    C = typeof(comp)

    # Dispatch to correct constructor depending on input given to direct call on component.
    DT = typeof(d)
    mod.eval(quote
        D.component(::$DT) = $comp
        (::$C)(n::Integer) = $comp.Number(n)
        (::$C)(names) = $comp.Names(names)
    end)

    # Display.
    mod.eval(quote
        $F.shortline(io::IO, model::Model, ::$C) = $class_shortline($d, io, model)
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
                using EcologicalNetworksDynamics: N, V, D, Network, Model
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
                    V.mask_view(D.NodeSubclass(c, N.class(n, c).parent), m)

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
# Implementation detail and extension points,
# along the whole blueprint sequence from construction to expansion.

#-------------------------------------------------------------------------------------------
# Construct.

# Names.
function construct(d::D.Class, ::Type{<:ClassNamesBlueprint}, input)
    names = NF.inputconvert(Vector{Symbol}, input)
    early_check(d, names) # Ignore the data possibly produced data for late checking.
    names
end

# Allow passing names as separate arguments.
construct(d::D.Class, BP::Type{<:ClassNamesBlueprint}, input...) = construct(d, BP, input)

# Number.
function construct(d::D.Class, ::Type{<:ClassNumberBlueprint}, input)
    n = NF.inputconvert(Int, input)
    early_check(d, n)
    n
end

#-------------------------------------------------------------------------------------------
# Early check (without model context).
# This is done once during construction and once prior to expansion.

# Names.
function early_check(d::D.Class, names::Vector{Symbol})
    # Forbid duplicates (triangular check).
    Class = D.CamelCaseSingular(d)
    already = OrderedDict{Symbol,Int}() # {name: index}
    for (i, name) in enumerate(names)
        if haskey(already, name)
            j = already[name]
            # HERE: the whole framework would benefit from a unified error story:
            # component authors would just have 1 error type to raise in case of trouble,
            # and the generic code should upgrade it accordingly.
            conserr("$Class $i and $j would be both named $(repr(name)).")
        end
        already[name] = i
    end
    names
end
early_check(d::D.Class, bp::ClassNamesBlueprint) = early_check(d, bp.names)

# Number.
function early_check(d::D.Class, n::Int)
    # Forbid negative number of nodes.
    n >= 0 && return n
    class = D.snake_case_plural(d)
    checkerr(n, "Cannot construct a negative number of $class.")
end
early_check(d::D.Class, bp::ClassNumberBlueprint) = early_check(d, bp.n)

#-------------------------------------------------------------------------------------------
# Late check (with model context).

# (not much to check in the general situation.)
late_check(::D.Class, ::Model, ::Blueprint, data) = data

#-------------------------------------------------------------------------------------------
# Expand.

# Names.
function expand!(d::D.Class, m::Model, names)
    class = D.class(d)
    network = NF.network(m)
    N.add_class!(network, class, names)
end
expand!(d::D.Class, m::Model, ::ClassNamesBlueprint, names) = expand!(d, m, names)

# Number (generate names).
expand!(d::D.Class, m::Model, ::ClassNumberBlueprint, n) =
    expand!(d, m, (Symbol(D.short_prefix(d), i) for i in 1:n))

# ==========================================================================================
# Display.

function class_shortline(d::D.Class, io::IO, m::Model)
    class = D.snake_case_plural(d)
    Class = D.CamelCaseSingular(d)
    names = getproperty(m, class)._names
    n = length(names)
    print(io, "$Class: $n ($(EN.join_elided(names, ", ")))")
end
