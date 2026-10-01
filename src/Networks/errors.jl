"""
Only throw from within the internals,
and ⚠ **prior to mutating** ⚠ any data within a transaction.
"""
struct NetworkError <: Exception
    mess::String
end
err(mess) = throw(NetworkError(mess))
Base.showerror(io::IO, e::NetworkError) = print(io, "Network error: $(e.mess)")
