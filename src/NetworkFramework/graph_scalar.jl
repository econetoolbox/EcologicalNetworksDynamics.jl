"""
Expand into a graph-level scalar given the value.
"""
abstract type GraphScalarBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new graph-level scalar data to the network.
The data is passed as-is to the internals, so it is enforced to be immutable.
"""
function define_graph_scalar(mod::Module, d::D.GraphField)
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
                const d = $d
                const T = $T

                mutable struct Raw <: NF.GraphScalarBlueprint
                    $field::T
                    @bp_construct(Raw)
                end
                export Raw
                NF.datatype(::Type{Raw}) = T
                NF.data(b::Raw) = b.$field
                $NF.register_blueprint(Raw, "raw $($("$singular")) value"; d)

                end
            end
        ).args |> last,
    )

    # ======================================================================================
    # The component itself.

    comp = mod.eval(
        quote
            $NF.define_component($(Meta.quot(Singular)), $mod; blueprints = [$bpmod])
        end,
    )
    C = typeof(comp)
    DT = typeof(d)
    mod.eval(
        quote
            D.component(::$DT) = $comp
            (::$C)(input) = $comp.Raw(input)
            $F.shortline(io::IO, model::Model, ::$C) =
                $graph_scalar_shortline($d, io, model)
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
                using EcologicalNetworksDynamics.NetworkFramework: NF, D, Network, Model
                const d = $d
                const props = $props
                const C = $C
                get_value(::Network, m::Model) = NF.get_value(m, d)
                NF.define_method(get_value; read_as = props, depends = [C])
                if !D.readonly(d)
                    function set_value!(::Network, m::Model, input)
                        low = NF._reassign(m, d, input)
                        NF.reassign!(m, d, low)
                    end
                    NF.define_method(set_value!; write_as = props, depends = [C])
                end
                end
            end
        ).args |> last,
    )

    comp

end

# ==========================================================================================
# Specialisation for this typical component type.
# The data may be aliased throughout the default lowering pipeline,
# because it has been checked for immutability anyway.

function expand!(m::Model, d::D.GraphField, low)
    field, n = D.field(d), N.network(m)
    N.add_field!(n, field, low)
end

function get_value(m::Model, d::D.GraphField)
    field, n = D.field(d), N.network(m)
    entry = n.data[field]
    N.read(entry) do value
        value # Just leak it: immutable.
    end
end

function reassign!(m::Model, d::D.GraphField, low)
    field, n = D.field(d), N.network(m)
    entry = n.data[field]
    N.reassign!(entry, low)
end

#-------------------------------------------------------------------------------------------
# Display.

function graph_scalar_shortline(d::D.GraphField, io, m::Model)
    cc = F.component_color
    fc = F.field_color
    field = D.field(d)
    Field = D.CamelCaseSingular(d)
    net = N.network(m)
    entry = net.data[field]
    read(entry) do value
        print(io, "$cc$Field$reset: $fc$(repr(value))$reset")
    end
end
