# Generate typical component bringing a new class.

"Expand into a new nodes class."
abstract type ClassBlueprint <: Blueprint end

"From raw nodes names."
abstract type ClassNames <: ClassBlueprint end

"From a number of nodes."
abstract type ClassNumber <: ClassBlueprint end

"Typical setup for a component bringing a new class to the network."
function define_class_component(mod::Module, s::SL.Class; blueprints = [])
    S = typeof(s)
    short_prefix, singular, plural, Singular, Plural = SL.name_variants(s)
    h, H, short_prefix = Meta.quot.((plural, Plural, short_prefix)) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    Blueprints = Symbol(Plural, :Blueprints)
    bpmod = mod.eval(
        (
            quote
                module $Blueprints
                import EcologicalNetworksDynamics.Interface:
                    IT, Model, @bp_construct
                const s = $s
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    bpmod.eval(quote
        mutable struct Names <: IT.ClassNames
            names::Vector{Symbol}
            @bp_construct Names
        end
        export Names
        $IT.register_blueprint(Names, "raw $($h) names"; s)
    end)

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    bpmod.eval(quote
        mutable struct Number <: IT.ClassNumber
            n::Int
            @bp_construct Number
        end
        export Number
        $IT.register_blueprint(Number, "number of $($h)"; s)
    end)

    # ======================================================================================
    # The component itself and generic blueprints constructors.
    CPname = s |> SL.componentname |> Meta.quot
    cp = IT.eval(
        quote
            define_component($CPname, $mod; blueprints = [$bpmod, $blueprints...])
        end,
    )
    CP = typeof(cp)

    # Dispatch to correct constructor depending on input given to direct call on component.
    IT.eval(quote
        SL.component(::$S) = $cp
        (::$CP)(n::Integer) = $cp.Number(n)
        (::$CP)(names::AbstractVector) = $cp.Names(names)
        (::$CP)(names::String) = $cp.Names(names)
    end)

    # Display.
    IT.eval(quote
        CS.shortline(io::IO, model::Model, ::$CP) = class_shortline($s, io, model)
    end)

    define_class_properties(mod, s; depends = [CP])

    (cp, CP)
end

# ==========================================================================================

function define_class_properties(mod::Module, s::SL.Class; depends = [])
    c = SL.classname(s)
    short_prefix, singular, plural, Singular, Plural = SL.name_variants(s)

    IT.define_propspace(plural)
    defmeth(fn, s) = IT.define_method(fn; depends, read_as = [:($plural.$s)])

    # Wrap all within a separate module
    # or identical definitions end up being considered the same functions.
    # https://julialang.zulipchat.com/#narrow/channel/137791-general/topic/Identity.20of.20local.20functions.2E/with/590238482
    Methods = Symbol(Plural, :Methods)
    mod.eval(
        (
            quote
                module $Methods
                using EcologicalNetworksDynamics.Interface:
                    ST, VW, SL, CS, Network, Model, @alias
                using OrderedCollections
                const defmeth, s, c = $defmeth, $s, $(Meta.quot(c))

                # Ordered index.
                ref_index(nw::Network) = ST.class(nw, c).index
                get_index(nw::Network) = deepcopy(ref_index(nw).forward)
                indices(nw::Network) = ST.node_indices(nw, c)

                # Nodes counts and nodes labels.
                # The 'ref' variant is more efficient but unexposed.
                get_number(nw::Network) = ST.n_nodes(nw, c)
                ref_names(nw::Network) = ref_index(nw).reverse
                get_names(::Network, md::Model) = VW.names_view(s, md)

                # Mask within parent class.
                get_parent_index(nw::Network) =
                    OrderedDict(l => i for (l, i) in zip(ref_names(nw), indices(nw)))
                mask(nw::Network, md::Model) =
                    VW.mask_view(SL.subclass(c, ST.class(nw, c).parent), md)

                defmeth(get_number, :number)
                defmeth(ref_names, :_names)
                defmeth(get_names, :names)
                defmeth(ref_index, :_index)
                defmeth(get_index, :index)
                defmeth(indices, :indices)
                defmeth(get_parent_index, :parent_index)
                defmeth(mask, :mask)

                @alias $c.count $c.number
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
    nw = ST.network(md)
    ST.add_class!(nw, c, names)
end

# From number (generate names).
function expand!(md::Model, s::SL.Class, n::Int)
    prefix = SL.short_prefix(s)
    names = (Symbol(prefix, i) for i in 1:n)
    expand!(md, s, names)
end

#-------------------------------------------------------------------------------------------
# Query.

obtain(vw::VW.NodeNameView, (r,)::Tuple{Ref}) = ST.to_label(ST.class(vw).index, r)
obtain(vw::VW.NodeMaskView, (r,)::Tuple{Symbol}) = ST.is_ref(ST.class(vw).index, r)
obtain(vw::VW.NodeMaskView, (r,)::Tuple{Int}) = r in ST.class(vw).restriction

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
