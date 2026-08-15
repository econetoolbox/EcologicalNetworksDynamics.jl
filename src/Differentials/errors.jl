struct GenerationError <: Exception
    message::String
end

generr(m) = throw(GenerationError(m))

function Base.showerror(io::IO, e::GenerationError)
    red = crayon"red"
    bold = crayon"bold"
    reset = crayon"reset"
    print(
        io,
        "$(red)$(bold)⚠ Error during simulation code generation. ⚠$(reset)\n\
         This is a bug in the package. \
         Consider reporting if you can reproduce with minimal example.\n\
         $(e.message)\n",
    )
end
