module TestUtils

using Test
using Crayons
blue = crayon"blue"
red = crayon"red"
bold = crayon"bold"
reset = crayon"reset"

# Draw separator.
sep(mess) = println("$blue$bold== $mess $(repeat("=", 80 - 4 - length(mess)))$reset")
export sep

eprint(args...; kwargs...) = print(stderr, args...; kwargs...)
eprintln(args...; kwargs...) = println(stderr, args...; kwargs...)
export eprint, eprintln

# Compare actual vs expected raw console display, "snapshot-testing" style,
# with helful summary in case of mismatch.
function is_repr(x, expected)
    actual = repr(x)
    actual == expected && return true
    eprintln("$(bold)CHECK FAILED:$reset The two console representations differ:\n\
              $(blue)expected:$reset $expected\n\
              $(red)  actual:$reset $actual")
    false
end
export is_repr

function is_disp(x, expected)
    io = IOBuffer()
    actual = show(IOContext(io, :limit => true, :displaysize => (20, 40)), "text/plain", x)
    actual = String(take!(io))
    actual == expected && return true
    eprintln("$(bold)CHECK FAILED:$reset The two console display differ:\n\
              $expected\n$bold---- ^^^ expected | actual vvv ----$reset\n$actual")
    a_it, e_it = eachsplit.((actual, expected), '\n')
    a_next = iterate(a_it)
    e_next = iterate(e_it)
    while true
        isnothing(a_next) && isnothing(e_next) && throw("Should be different, right?")
        if isnothing(a_next)
            exp, _ = e_next
            println("$(bold)Missing line:$reset\n$red$exp$reset")
            break
        end
        if isnothing(e_next)
            act, _ = a_next
            println("$(bold)Unexpected line:$reset\n$blue$exp$reset")
            break
        end
        exp, e_state = e_next
        act, a_state = a_next
        if exp != act
            println("$(bold)First differing lines:$reset\n\
                     $blue$exp$reset\n\
                     $bold---- ^^^ expected | actual vvv----$reset\n\
                     $red$act$reset")
            break
        end
        a_next = iterate(a_it, a_state)
        e_next = iterate(e_it, e_state)
    end
    false
end
export is_disp

end
