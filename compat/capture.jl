using TestEnv
using Pkg

here = dirname(Base.active_project())
destination = joinpath(here, "pinned_test_env")
mkpath(destination)

# Get current testing environment, assuming it has just been successful.
TestEnv.activate("EcologicalNetworksDynamics")

# Pin all dependencies in place.
Pkg.pin(all_pkgs=true)

# Save corresponding environment for checking in.
project = Base.active_project()
manifest = joinpath(dirname(project), "Manifest.toml")
cp(project, joinpath(destination, "Project.toml"), force=true)
cp(manifest, joinpath(destination, "Manifest.toml"), force=true)

# Reconnect with a dev-dependency to this very revision of the code.
Pkg.activate(destination)
Pkg.develop(path="..")
