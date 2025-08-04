struct NetworkError <: Exception
    mess::String
end
err(mess) = throw(NetworkError(mess))
Base.showerror(io::IO, e::NetworkError) = print(io, "Network error: $(e.mess)")
