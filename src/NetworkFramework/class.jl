# Generate typical component bringing a new class.

"Expand into a new nodes class."
abstract type ClassBlueprint <: Blueprint end

"From raw nodes names."
abstract type ClassNames <: ClassBlueprint end

"From a number of nodes."
abstract type ClassNumber <: ClassBlueprint end

"Typical setup for a component bringing a new class to the network."
function define_class_component(mod::Module, s::SL.Class)
    S = typeof(s)
    short_prefix, singular, plural, Singular, Plural = SL.name_variants(s)
    Plural_ = Symbol(Plural, :_) # Blueprints module name.
    _Plural = Symbol(:_, Plural) # Component type name.
    h, H, short_prefix = Meta.quot.((plural, Plural, short_prefix)) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    bpmod = mod.eval(
        (
            quote
                module $Plural_
                import EcologicalNetworksDynamics.NetworkFramework: NF, Model, @bp_construct
                const s = $s
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    bpmod.eval(quote
        mutable struct Names <: NF.ClassNames
            names::Vector{Symbol}
            @bp_construct Names
        end
        export Names
        $NF.register_blueprint(Names, "raw $($h) names"; s)
    end)

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    bpmod.eval(quote
        mutable struct Number <: NF.ClassNumber
            n::Int
            @bp_construct Number
        end
        export Number
        $NF.register_blueprint(Number, "number of $($h)"; s)
    end)

    # ======================================================================================
    # The component itself and generic blueprints constructors.
    cp = NF.eval(
        quote
            define_component($(Meta.quot(Plural)), $mod; blueprints = ($bpmod,))
        end,
    )
    CP = typeof(cp)

    # Dispatch to correct constructor depending on input given to direct call on component.
    NF.eval(quote
        SL.component(::$S) = $cp
        (::$CP)(n::Integer) = $cp.Number(n)
        (::$CP)(names::AbstractVector) = $cp.Names(names)
        (::$CP)(names::String) = $cp.Names(names)
    end)

    # Display.
    NF.eval(quote
        CS.shortline(io::IO, model::Model, ::$CP) = class_shortline($s, io, model)
    end)

    define_class_properties(mod, s; depends = [CP])

    (cp, CP)
end

# ==========================================================================================

function define_class_properties(mod::Module, s::SL.Class; depends = [])
    c = SL.classname(s)
    short_prefix, singular, plural, Singular, Plural = SL.name_variants(s)

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
                using EcologicalNetworksDynamics.NetworkFramework: N, V, SL, Network, Model
                using OrderedCollections
                const defmeth, s, c = $defmeth, $s, $(Meta.quot(c))

                # Ordered index.
                ref_index(nw::Network) = N.class(nw, c).index
                get_index(nw::Network) = deepcopy(ref_index(nw).forward)
                indices(nw::Network) = N.node_indices(nw, c)

                # Nodes counts and nodes labels.
                # The 'ref' variant is more efficient but unexposed.
                get_number(nw::Network) = N.n_nodes(nw, c)
                ref_names(nw::Network) = ref_index(nw).reverse
                get_names(::Network, md::Model) = V.names_view(s, md)

                # Mask within parent class.
                get_parent_index(nw::Network) =
                    OrderedDict(l => i for (l, i) in zip(ref_names(nw), indices(nw)))
                mask(nw::Network, md::Model) =
                    V.mask_view(SL.subclass(c, N.class(nw, c).parent), md)

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

#-------------------------------------------------------------------------------------------
# Construct.

# Allow passing names as separate arguments.
construct(BP::Type{<:ClassNames}, first, second, rest...) =
    construct(BP, (first, second, rest...))

#-------------------------------------------------------------------------------------------
# Early check.

# Names: forbid duplicates (triangular check).
function early_check(s::SL.Class, names::Vector{Symbol})
    already = OrderedDict{Symbol,Int}() # {name: index}
    for (i, name) in enumerate(names)
        if haskey(already, name)
            Class = SL.CamelCaseSingular(s)
            j = already[name]
            checkerr(name,
                "$Class $j and $i would both be named $cyan$(repr(name))$reset.";
                uref = (i,))
        end
        already[name] = i
    end
    names
end

# Number: forbid negative number of nodes.
function early_check(s::SL.Class, n::Int)
    n >= 0 && return n
    class = SL.snake_case_plural(s)
    checkerr(n, "Cannot construct a negative number of $class nodes.")
end

#-------------------------------------------------------------------------------------------
# Expand.

# From names.
function expand!(md::Model, s::SL.Class, names)
    c = SL.classname(s)
    nw = N.network(md)
    N.add_class!(nw, c, names)
end

# From number (generate names).
function expand!(md::Model, bp::ClassNumber, n)
    s = selector(bp)
    prefix = SL.short_prefix(s)
    names = (Symbol(prefix, i) for i in 1:n)
    expand!(md, s, names)
end

#-------------------------------------------------------------------------------------------
# Query.

obtain(vw::V.NodeNameView, (r,)::Tuple{Ref}) = N.to_label(N.class(vw).index, r)
obtain(vw::V.NodeMaskView, (r,)::Tuple{Symbol}) = N.is_ref(N.class(vw).index, r)
obtain(vw::V.NodeMaskView, (r,)::Tuple{Int}) = r in N.class(vw).restriction

#-------------------------------------------------------------------------------------------
# Display.

function class_shortline(s::SL.Class, io::IO, md::Model)
    cc, fc, rs = CS.component_color, CS.field_color, reset
    class = SL.snake_case_plural(s)
    Class = SL.CamelCaseSingular(s)
    names = getproperty(md, class)._names
    n = length(names)
    names = join_elided(names, ", "; coleach = green)
    print(io, "$cc$Class$rs: $fc$n$rs ($names)")
end
