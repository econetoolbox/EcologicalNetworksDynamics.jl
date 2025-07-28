"""
Prototype the data structure at the heart of the ecological model.

A 'network' represents a directed graph
structured in several nodes equivalence 'classes'
and several edges 'webs' connecting classes together.

A 'class' is one particular subset of graph nodes.
Classes derive from each other into a hierarchy tree:
a 'subclass' is one particular subset of the nodes in its parent class.
The root class contains all nodes in the graph.

A 'web' is one particular subset of edges in the graph,
tied to an ordered pair of 'source' and 'target' classes.
A web only contains edges
whose origin is a node in the source class and
whose destination is a node in the target class.
No edge in the graph is not part of a web.

Classes and webs are designed by unique `Symbol` identifiers.
Nodes are 'referenced' by unique `Symbol` identifiers called 'labels'.
Nodes are also *ordered*.
Their order in every class is consistent with the order of the root class.
As a consequence, nodes can also be 'referenced'
by an (`Int`eger, class) pair called an 'index'.

New classes and new webs can be inserted to the network,
but they are *immutable* once set:
identifiers and labels cannot change,
nodes ordering cannot change,
nodes cannot be added to a class or removed from a class,
edges cannot be added to a web or removed from a web.
One exception is that nodes can be *appended* to the root class,
so as to introduce new subclasses,
but without reordering or reindexing existing nodes.

In addition to classes and webs,
the network also holds *mutable* associated 'data'
structured in 3 different 'levels':
- At 'graph' level: scalar data whose scope encompasses the whole network.
- At 'node' level: vector data whose scope is bound to one class.
- At 'edge' level: matrix data whose scope is bound to one web.

Both the network topology and associated mutable data
are protected by a ["Copy-On-Write"][COW] pattern,
allowing the network to be cheaply shared, copied and forked,
although __NOT ACCROSS THREADS__ yet.

__TODO__ (easy): provide a reliable way to get a fully owned network
                 for sending accross threads.
__TODO__ (hard): make the Network thread-safe.

This pattern is implemented with three levels of indirection:

- `Fields` (unexposed) protect raw data
   and keep track of the current number of networks they are involved in,
   effectively ["Reference counting"][RC] the data for networks.
   The counter is decreased whenever an owning network is garbage-collected.

- `Entries` (unexposed) protect fields
  by [Boxing] them behind a reassignable reference
  so they can be transparently updated upon mutation
  without mutating the network itself.

- `Views` (exposed) protect the pattern
  by referencing entries to ensure that copying
  happens prior to mutation,
  and by referencing the network itself
  to prevent garbage collection as they are live.

[COW]: https://en.wikipedia.org/wiki/Copy-on-write
[RC]: https://en.wikipedia.org/wiki/Reference_counting
[Boxing]: https://en.wikipedia.org/wiki/Boxing_(computer_programming)
"""

module Networks

using OrderedCollections
using SparseArrays
import .Iterators as I

# Useful addition to iterators provided the closure returns Union{Some,Nothing}.
filter_map(f, v) = I.map(something, I.filter(!isnothing, I.map(f, v)))

using ..Display

const Option{T} = Union{Nothing,T}
const Index = OrderedDict{Symbol,Int}

struct NetworkError <: Exception
    mess::String
end
err(mess) = throw(NetworkError(mess))
Base.showerror(io::IO, e::NetworkError) = print(io, "Network error: $(e.mess)")

include("./data.jl")
include("./restrictions.jl")
include("./topologies.jl")
include("./class.jl")
include("./web.jl")
include("./network.jl")
include("./views.jl")
include("./nodes_exports.jl")
include("./primitives.jl")

end
