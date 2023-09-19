mutable struct ObjectRef
    oid::ray_jll.ObjectIDAllocated
    owner_address::Union{ray_jll.AddressAllocated,Nothing}
    serialized_object_status::String

    function ObjectRef(oid, owner_address, serialized_object_status;
                       add_local_ref=true)
        if add_local_ref
            worker = ray_jll.GetCoreWorker()
            ray_jll.AddLocalReference(worker, oid)
        end
        objref = new(oid, owner_address, serialized_object_status)
        return finalizer(objref) do objref
            # putting finalizer behind `@async` may not be necessary since docs
            # suggest that you should `ccall` IO functions.  But doing it this
            # way allows us to do things like debug logging...
            errormonitor(@async finalize_object_ref(objref))
            return nothing
        end
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

function finalize_object_ref(obj::ObjectRef)
    @debug "Removing local ref for ObjectID $(obj.oid)"
    worker = ray_jll.GetCoreWorker()
    ray_jll.RemoveLocalReference(worker, obj.oid)
    return nothing
end

ObjectRef(oid::ray_jll.ObjectIDAllocated; kwargs...) = ObjectRef(oid, nothing, ""; kwargs...)
ObjectRef(hex_str::AbstractString; kwargs...) = ObjectRef(ray_jll.FromHex(ray_jll.ObjectID, hex_str); kwargs...)
hex_identifier(obj_ref::ObjectRef) = String(ray_jll.Hex(obj_ref.oid))
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
    worker = ray_jll.GetCoreWorker()

    outer_object_id = if outer_obj_ref !== nothing
        outer_obj_ref.oid
    else
        ray_jll.FromNil(ray_jll.ObjectID)
    end

    if !isnothing(obj_ref.owner_address) && !has_owner(obj_ref)
        # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L3329
        # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.h#L543
        ray_jll.RegisterOwnershipInfoAndResolveFuture(worker, obj_ref.oid, outer_object_id,
                                                      obj_ref.owner_address,
                                                      obj_ref.serialized_object_status)
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
    ray_jll.GetOwnershipInfo(worker, obj_ref.oid, CxxPtr(owner_address), CxxPtr(serialized_object_status))
    owner_address_str = String(ray_jll.SerializeAsString(owner_address))
    serialized_object_status = String(serialized_object_status)

    serialize_type(s, typeof(obj_ref))
    serialize(s, hex_str)
    serialize(s, owner_address_str)
    serialize(s, serialized_object_status)

    return nothing
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ObjectRef})
    hex_str = deserialize(s)
    owner_address_str = deserialize(s)
    serialized_object_status = deserialize(s)

    object_id = ray_jll.FromHex(ray_jll.ObjectID, hex_str)
    owner_address = nothing
    if !isempty(owner_address_str)
        owner_address = ray_jll.Address()
        ray_jll.ParseFromString(owner_address, owner_address_str)
    end

    return ObjectRef(object_id, owner_address, serialized_object_status)
end
