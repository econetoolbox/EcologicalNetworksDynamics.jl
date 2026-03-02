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
    blueprints =
        mod.eval.(
            (
                quote
                    module $Plural_
                    import EcologicalNetworksDynamics:
                        N, F, NF, Blueprint, @blueprint, @component
                    const d = $d
                    end
                end
            ).args
        ) |> last

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    blueprints.eval(
        quote
            mutable struct Names <: Blueprint
                names::Vector{Symbol}
                Names(names) = new(construct_from_iterable(d, Vector{Symbol}, names))
                Names(names...) = new(construct_from_iterable(d, Vector{Symbol}, names))
                Names(names::Vector{Symbol}) = new(names) # Alias if type-exact.
            end

            # Declare as a blueprint.
            @blueprint Names "raw $($s) names"
            export Names

            # Verify blueprint values.
            F.early_check(bp::Names) = $early_check(d, bp.names)

            # Expand into a new compartment.
            F.expand!(model, bp::Names, _) =
                Networks.add_class!(network(model), $s, bp.names)

        end,
    )

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    blueprints.eval(
        quote
            mutable struct Number <: Blueprint
                n::UInt
            end
            @blueprint Number "number of $($s)"
            export Number
            F.expand!(model, bp::Number, _) = expand_from_vector!(
                network(model),
                (Symbol($short_prefix, i) for i in 1:bp.n),
            )
        end,
    )

    # ======================================================================================
    # The component itself and generic blueprints constructors.
    mod.eval(quote
        # XXX: if all components wrap like this, no need for the macro anymore?
        @component $Plural{Network} blueprints($Plural_)
    end) # Need to reach toplevel first to access generated values, right?

    DT = typeof(d)
    mod.eval(quote
        D.component(::$DT) = $Plural
        # Build from a number or default to names.
        (::$_Plural)(n::Integer) = $Plural.Number(n)
        (::$_Plural)(names) = $Plural.Names(names)
    end)

    # Display.
    mod.eval(
        quote
            Framework.shortline(io::IO, model::Model, ::$_Plural) =
                $class_shortline(io, model, d)
        end,
    )

    define_class_properties(mod, d, :(depends($Plural)))
end

# ==========================================================================================

function define_class_properties(
    mod::Module,
    d::NodeClass,
    deps::Expr, # As in a regular call to @method.
)
    short_prefix, singular, plural, Singular, Plural = D.name_variants(d)
    s = Meta.quot(plural)
    M = Symbol(Plural, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $plural

        module $M
        import EcologicalNetworksDynamics: N, Network, Model, @method, Views

        # Nodes counts and nodes labels.
        # The 'ref' variant is more efficient but unexposed.
        get_number(m::Network) = N.n_nodes(m, $s)
        ref_names(m::Network) = N.class(m, $s).index.reverse
        get_names(::Network, m::Model) = Views.nodes_names_view(m, $s)
        @method $m $M.get_number $deps read_as($plural.number)
        @method $m $M.ref_names $deps read_as($plural._names)
        @method $m $M.get_names $deps read_as($plural.names)

        # Ordered index.
        ref_index(m::Network) = N.class(m, $s).index.forward
        get_index(m::Network) = deepcopy(N.ref_index(m))
        indices(m::Network) = N.node_indices(m, $s)
        get_parent_index(m::Network) =
            OrderedDict(l => i for (l, i) in zip(ref_names(m), indices(m)))
        @method $m $M.ref_index $deps read_as($plural._index)
        @method $m $M.get_index $deps read_as($plural.index)
        @method $m $M.indices $deps read_as($plural.indices)
        @method $m $M.get_parent_index $deps read_as($plural.parent_index)

        # Mask within parent class.
        mask(i::Network, m::Model) = N.nodes_mask_view(m, ($s, class(i, $s).parent))
        @method $m $M.mask $deps read_as($plural.mask)

        end
    end

    mod.eval.(xp.args)
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

# Display.
function class_shortline(io::IO, model::Model, d::NodeClass)
    class = D.snake_case_plural(d)
    Class = D.CamelCaseSingular(d)
    names = getproperty(model, class)._names
    n = length(names)
    print(io, "$Class: $n ($(EN.join_elided(names, ", ")))")
end
