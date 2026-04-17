# Typical setup for a component bringing a new field to a network subclass.
# Subclasses are also regular classes,
# so the component definition first relies on the regular class one,
# but it is *extended* with sparsity/parenting concepts.

function define_sparse_node_field_component(
    mod::Module,
    d::ExpandedNodeField;
    blueprints = nothing,
    requires = (),
)
    # Mostly delegate to regular class, but also introduce sparse blueprints.
    nf = NodeField(d)
    if isnothing(blueprints)
        blueprints = quote end
    end
    # HERE: introduce sparse blueprints prior to calling the following.
    # HERE: figure how to inject sparsity into component-level constructor dispatcher.
    define_node_field_component(mod, nf; blueprints, requires)

end
