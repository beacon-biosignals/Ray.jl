# setup some modules for teh function manager tests...
module MyMod
f(x) = x + 1

module MySubMod
f(x) = x - 1
end # module MM

end # module M

module NotMyMod
using ..MyMod: f
g(x) = x - 1
end
