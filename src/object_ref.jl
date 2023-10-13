mutable struct ObjectRef
    oid_hex::String
    owner_address_json::Union{String,Nothing}
    serialized_object_status::String

    function ObjectRef(oid_hex, owner_address_json, serialized_object_status;
                       add_local_ref=true)
        if owner_address_json !== nothing && isempty(owner_address_json)
            owner_address_json = nothing
        end
        objref = new(oid_hex, owner_address_json, serialized_object_status)
        if add_local_ref
            worker = ray_jll.GetCoreWorker()
            ray_jll.AddLocalReference(worker, objref.oid)
        end
        finalizer(objref) do objref
            errormonitor(@async finalize_object_ref(objref))
            return nothing
        end
        return objref
    end
end

function finalize_object_ref(obj::ObjectRef)
    @debug "Removing local ref for ObjectID $(obj.oid_hex)"
    # XXX: should make sure core worker is still initialized before calling it
    # to avoid segfaults
    worker = ray_jll.GetCoreWorker()
    oid = ray_jll.FromHex(ray_jll.ObjectID, obj.oid_hex)
    ray_jll.RemoveLocalReference(worker, oid)
    return nothing
end

# we overload getproperty for :oid and :owner_address (from previous
# implementation) which were replaced with String-serialized versions that are
# safe references, instead of holding onto C++ managed memory
function Base.getproperty(x::ObjectRef, prop::Symbol)
    return if prop == :oid
        ray_jll.FromHex(ray_jll.ObjectID, getfield(x, :oid_hex))
    elseif prop == :owner_address
        owner_address_json = getfield(x, :owner_address_json)
        isnothing(owner_address_json) && return nothing
        std_str = safe_convert(StdString, owner_address_json)
        ray_jll.JsonStringToMessage(ray_jll.Address, std_str)
    else
        getfield(x, prop)
    end
end

# in order to actually increment the local ref count appropriately when we
# `deepcopy` an ObjectRef and setup the appropriate finalizer, this
# specialization calls the constructor after deepcopying the fields.
function Base.deepcopy_internal(x::ObjectRef, stackdict::IdDict)
    fieldnames = Base.fieldnames(typeof(x))
    fieldcopies = ntuple(length(fieldnames)) do i
        @debug "deep copying x.$(fieldnames[i])"
        fieldval = getfield(x, fieldnames[i])
        return Base.deepcopy_internal(fieldval, stackdict)
    end

    xcp = ObjectRef(fieldcopies...; add_local_ref=true)
    stackdict[x] = xcp

    return xcp
end

ObjectRef(oid::ray_jll.ObjectID; kwargs...) = ObjectRef(ray_jll.Hex(oid); kwargs...)
ObjectRef(oid_hex::AbstractString; kwargs...) = ObjectRef(oid_hex, nothing, ""; kwargs...)
hex_identifier(obj_ref::ObjectRef) = obj_ref.oid_hex
Base.:(==)(a::ObjectRef, b::ObjectRef) = hex_identifier(a) == hex_identifier(b)

function Base.hash(obj_ref::ObjectRef, h::UInt)
    h = hash(ObjectRef, h)
    h = hash(hex_identifier(obj_ref), h)
    return h
end

function Base.show(io::IO, obj_ref::ObjectRef)
    write(io, "ObjectRef(\"", hex_identifier(obj_ref), "\")")
    return nothing
end

# Mirrors the functionality of the Python Ray function `get_owner_address`
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L3308
function get_owner_address(obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()
    owner_address = ray_jll.Address()
    status = ray_jll.GetOwnerAddress(worker, obj_ref.oid, CxxPtr(owner_address))
    ray_jll.check_status(status)
    return owner_address
end

# TODO: A more efficiently `CoreWorker::HasOwner` exists but is private
function has_owner(obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()
    owner_address = ray_jll.Address()
    status = ray_jll.GetOwnerAddress(worker, obj_ref.oid, CxxPtr(owner_address))
    return !isempty(ray_jll.SerializeAsString(owner_address))
end

# TODO: this is not currently used pending investigation of how to properly handle ownership
# see https://github.com/beacon-biosignals/Ray.jl/issues/77#issuecomment-1717675779
# and https://github.com/beacon-biosignals/Ray.jl/pull/108
function _register_ownership(obj_ref::ObjectRef, outer_obj_ref::Union{ObjectRef,Nothing})
    @debug """Registering ownership for $(obj_ref)
              owner address: $(obj_ref.owner_address)
              status: $(bytes2hex(codeunits(obj_ref.serialized_object_status)))
              contained in $(outer_obj_ref)"""

    outer_object_id = if outer_obj_ref !== nothing
        outer_obj_ref.oid
    else
        ray_jll.FromNil(ray_jll.ObjectID)
    end

    # we've overloaded getproperty for this one to create the actual owner ref
    owner_address = obj_ref.owner_address

    worker = ray_jll.GetCoreWorker()
    if !isnothing(obj_ref.owner_address) && !has_owner(obj_ref)
        # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L3329
        # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.h#L543
        ray_jll.RegisterOwnershipInfoAndResolveFuture(worker, obj_ref.oid, outer_object_id,
                                                      owner_address,
                                                      obj_ref.serialized_object_status)
    else
        if isnothing(obj_ref.owner_address)
            @debug "attempted to register ownership but owner address is nothing: $(obj_ref)"
        end
        if has_owner(obj_ref)
            @debug "attempted to register ownership but object already has known owner: $(obj_ref)"
        end
    end

    return nothing
end

# We cannot serialize pointers between processes
function Serialization.serialize(s::AbstractSerializer, obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()

    hex_str = hex_identifier(obj_ref)
    owner_address = ray_jll.Address()
    serialized_object_status = StdString()

    # Prefer serializing ownership information from the core worker backend
    ray_jll.GetOwnershipInfo(worker, obj_ref.oid, CxxPtr(owner_address),
                             CxxPtr(serialized_object_status))

    @debug "serialize ObjectRef:\noid: $hex_str\nowner address $owner_address"

    owner_address_json = safe_convert(String, ray_jll.MessageToJsonString(owner_address))
    serialized_object_status = safe_convert(String, serialized_object_status)

    serialize_type(s, typeof(obj_ref))
    serialize(s, hex_str)
    serialize(s, owner_address_json)
    serialize(s, serialized_object_status)

    return nothing
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ObjectRef})
    hex_str = deserialize(s)
    owner_address_json = deserialize(s)
    serialized_object_status = deserialize(s)

    @debug begin
        owner_address = nothing
        if !isempty(owner_address_json)
            std_str = safe_convert(StdString, owner_address_json)
            owner_address = ray_jll.JsonStringToMessage(ray_jll.Address, std_str)
        end
        "deserialize ObjectRef:\noid: $hex_str\nowner address: $owner_address"
    end

    return ObjectRef(hex_str, owner_address_json, serialized_object_status)
end

safe_convert(::Type{String}, str::AbstractString) = convert(String, str)

# Using `collect` and `ncodeunits` to ensure that the entire string is captured and not just
# up to the first null character: https://github.com/JuliaInterop/CxxWrap.jl/pull/378
safe_convert(::Type{String}, str::StdString) = String(collect(str))
safe_convert(::Type{StdString}, str::AbstractString) = StdString(str, ncodeunits(str))
