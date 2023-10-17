mutable struct ObjectRef
    oid_hex::String

    function ObjectRef(oid_hex; add_local_ref=true)
        objref = new(oid_hex)
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

ObjectRef(oid::ray_jll.ObjectID; kwargs...) = ObjectRef(ray_jll.Hex(oid); kwargs...)

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

function _get_ownership_info(obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()
    owner_address = ray_jll.Address()
    serialized_object_status = StdString()

    ray_jll.GetOwnershipInfo(worker, obj_ref.oid, CxxPtr(owner_address),
                             CxxPtr(serialized_object_status))

    return owner_address, serialized_object_status
end

# TODO: this is not currently used pending investigation of how to properly handle ownership
# see https://github.com/beacon-biosignals/Ray.jl/issues/77#issuecomment-1717675779
# and https://github.com/beacon-biosignals/Ray.jl/pull/108
function _register_ownership(obj_ref::ObjectRef, outer_obj_ref::Union{ObjectRef,Nothing},
                             owner_address::ray_jll.Address,
                             serialized_object_status::String)
    @debug """Registering ownership for $(obj_ref)
              owner address: $(owner_address)
              status: $(bytes2hex(codeunits(serialized_object_status)))
              contained in $(outer_obj_ref)"""

    outer_object_id = if outer_obj_ref !== nothing
        outer_obj_ref.oid
    else
        ray_jll.FromNil(ray_jll.ObjectID)
    end

    worker = ray_jll.GetCoreWorker()
    if !has_owner(obj_ref)
        serialized_object_status = safe_convert(StdString, serialized_object_status)

        # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L3329
        # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.h#L543
        ray_jll.RegisterOwnershipInfoAndResolveFuture(worker, obj_ref.oid, outer_object_id,
                                                      owner_address,
                                                      serialized_object_status)
    else
        @debug "attempted to register ownership but object already has known owner: $(obj_ref)"
    end

    return nothing
end

# We cannot serialize pointers between processes
function Serialization.serialize(s::AbstractSerializer, obj_ref::ObjectRef)
    serialize_type(s, typeof(obj_ref))
    serialize(s, hex_identifier(obj_ref))
    return nothing
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ObjectRef})
    return ObjectRef(deserialize(s))
end
