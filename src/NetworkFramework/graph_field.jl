"Expand into a graph-level scalar given the value."
abstract type GraphScalarBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new graph-level scalar data to the network.
The data is passed as-is to the internals, so it is enforced to be immutable.
Returns the defined component and its type.
"""
function define_graph_field(mod::Module, d::D.GraphField)
    _D = typeof(d)
    shortname, singular, Singular = D.name_variants(d)
    Singular_ = Symbol(Singular, :_)

    T = D.type(d)
    N.is_deep_immutable(T) || throw(
        "Cannot pick this type for graph-level scalar data because it is mutable: $T.",
    )

    # ======================================================================================
    # Only one blueprint for now.

    # Prepare dedicated blueprints module and populate namespace.
    field = shortname
    bpmod = mod.eval(
        (
            quote
                module $Singular_
                import EcologicalNetworksDynamics.NetworkFramework: NF, @bp_construct
                const d, T = $d, $T

                mutable struct Raw <: NF.GraphScalarBlueprint
                    $field::T
                    @bp_construct Raw
                end
                export Raw
                NF.register_blueprint(Raw, "raw $($("$singular")) value"; d)

                end
            end
        ).args |> last,
    )

    # ======================================================================================
    # The component itself.

    cp = NF.eval(
        quote # Need to reach toplevel first to access generated values.
            define_component($(Meta.quot(Singular)), $mod; blueprints = ($bpmod,))
        end,
    )
    CP = typeof(cp)
    NF.eval(
        quote
            D.component(::$_D) = $cp
            (::$CP)(input) = $cp.Raw(input)
            F.shortline(io::IO, md::Model, ::$CP) = graph_scalar_shortline($d, io, md)
        end,
    )

    # ======================================================================================
    # Queries.

    M = Symbol(Singular, :Methods)
    props = [D.field(d), shortname]
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics.NetworkFramework:
                    NF, D, Network, Model, WholeData
                const d, CP, props = $d, $CP, $props
                get_value(::Network, md::Model) = NF.get_value(md, d)
                NF.define_method(get_value; read_as = props, depends = (CP,))
                if !D.readonly(d)
                    set_value!(::Network, md::Model, input) =
                        NF.mut_set!(md, d, WholeData, input)
                    NF.define_method(set_value!; write_as = props, depends = (CP,))
                end
                end
            end
        ).args |> last,
    )

    (cp, CP)

end

# ==========================================================================================
# Specialisation for this typical component type.
# The data may be aliased throughout the default lowering pipeline,
# because it has been checked for immutability anyway.

function expand!(md::Model, d::D.GraphField, low)
    nw, f = N.network(md), D.field(d)
    N.add_field!(nw, f, low)
end

function get_value(md::Model, d::D.GraphField)
    entry = N.entry(md, d)
    N.read(entry) do value
        value # Just leak it: immutable.
    end
end

function mutate!(md::Model, d::D.GraphField, ::_WholeData, low)
    entry = N.entry(md, d)
    N.reassign!(entry, low)
end

#-------------------------------------------------------------------------------------------
# Display.

function graph_scalar_shortline(d::D.GraphField, io, md::Model)
    cc = F.component_color
    fc = F.field_color
    Field = D.CamelCaseSingular(d)
    entry = N.entry(md, d)
    read(entry) do value
        print(io, "$cc$Field$reset: $fc$(repr(value))$reset")
    end
end
