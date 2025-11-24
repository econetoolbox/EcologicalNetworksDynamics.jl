# HERE: attempt to capture anything needed
# to define a component bringing a new class to the network.
# Extensibility required, but avoid it being noisy if unused.
# This **may** bypass @components_macro, @blueprint_macro and @expose_data.

function define_class_component()
    # Generated code prototype for an imaginary component called `Class`,
    # used as a placeholder.
    quote
        # ==================================================================================
        # Blueprints for the component.
        module ClassBlueprints
            #-------------------------------------------------------------------------------
            # Construct from a given set of names.
            mutable struct Names
                names::Vector{Symbol}
            end
        end
    end
end
