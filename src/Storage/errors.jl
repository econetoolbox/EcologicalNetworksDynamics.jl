"""
Only throw from within the internals,
and ⚠ **prior to mutating** ⚠ any data within a transaction.
"""
struct StorageError <: Exception
    mess::String
end
err(mess) = throw(StorageError(mess))
Base.showerror(io::IO, e::StorageError) = print(io, "Storage error: $(e.mess)")
