"""
Typical setup for a component bringing a new class to the network.
"""
function define_class_component(mod::Module, d::NodeClass)
    short_prefix, singular, plural, Singular, Plural = D.name_variants(d)
    Plural_ = Symbol(Plural, :_) # Blueprints module name.
    _Plural = Symbol(:_, Plural) # Component type name.
    s, S, short_prefix = Meta.quot.((plural, Plural, short_prefix)) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    bpmod =
        mod.eval.((
            quote
                module $Plural_
                import EcologicalNetworksDynamics: N, F, NF, Blueprint
                const d = $d
                end
            end
        ).args) |> last

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    bpmod.eval(quote
        mutable struct Names <: Blueprint
            names::Vector{Symbol}
            Names(names) = new(NF.inputconvert(Vector{Symbol}, names))
            Names(names...) = new([NF.inputconvert(Symbol, n) for n in names])
            Names(names::Vector{Symbol}) = new(names) # Alias if type-exact.
        end

        # Declare as a blueprint.
        NF.define_blueprint(Names, "raw $($s) names")
        # Export so it gets picked by `NF.define_component` when passing `bpmod` later.
        export Names

        # Verify blueprint values.
        F.early_check(bp::Names) = $early_check(d, bp.names)

        # Expand into a new compartment.
        F.expand!(model, bp::Names) = $expand!(d, model, bp.names)

    end)

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    bpmod.eval(
        quote
            mutable struct Number <: Blueprint
                n::Int
            end
            NF.define_blueprint(Number, "number of $($s)")
            export Number
            F.early_check(bp::Number) = $early_check(d, bp.n)
            F.expand!(model, bp::Number) =
                $expand!(d, model, (Symbol($short_prefix, i) for i in 1:bp.n))
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
end

# ==========================================================================================

function define_class_properties(mod::Module, d::NodeClass; depends = [])
    short_prefix, singular, plural, Singular, Plural = D.name_variants(d)

    NF.define_propspace(plural)
    defmeth(fn, s) = NF.define_method(fn; depends, read_as = [:($plural.$s)])

    # Wrap all within a separate module
    # or identical definitions end up being considered the same functions.
    # https://julialang.zulipchat.com/#narrow/channel/137791-general/topic/Identity.20of.20local.20functions.2E/with/590238482
    M = Symbol(Plural, :Methods)
    xp =
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
                get_names(::Network, m::Model) = V.names_view(m, d)

                # Mask within parent class.
                get_parent_index(n::Network) =
                    OrderedDict(l => i for (l, i) in zip(ref_names(n), indices(n)))
                mask(n::Network, m::Model) =
                    V.mask_view(m, D.NodeMask(c, N.class(n, c).parent))

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
        ).args |> last

    mod.eval(xp)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work.

# Forbid duplicates (triangular check).
function early_check(d::NodeClass, names::Vector{Symbol})
    Class = D.CamelCaseSingular(d)
    already = OrderedDict{Symbol,Int}() # {name: index}
    for (i, name) in enumerate(names)
        if haskey(already, name)
            j = already[name]
            F.checkfails("$Class $i and $j are both named $(repr(name)).")
        end
        already[name] = i
    end
    names
end

# Forbid negative number of nodes.
function early_check(d::NodeClass, n::Int)
    class = D.snake_case_plural(d)
    n >= 0 || F.checkfails("Cannot construct a negative number of $class: $n.")
end

function expand!(d::NodeClass, model::Model, names)
    class = D.class(d)
    network = NF.network(model)
    N.add_class!(network, class, names)
end

# Display.
function class_shortline(d::NodeClass, io::IO, model::Model)
    class = D.snake_case_plural(d)
    Class = D.CamelCaseSingular(d)
    names = getproperty(model, class)._names
    n = length(names)
    print(io, "$Class: $n ($(EN.join_elided(names, ", ")))")
end
