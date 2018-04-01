#types used by kRPC and type conversion utilities

#part of runtime support
#indicate class and enum membership
module kRPCTypes
abstract type Class end
abstract type Enum end
end

#type helper functions

function getWireValue(arg::Union{Int32,Int64,Float32,Float64,UInt32,UInt64})
    opb = PipeBuffer()
    ProtoBuf.write_fixed(opb, arg)
    return readavailable(opb)
end

function getWireValue(arg::Bool)
    opb = PipeBuffer()
    ProtoBuf.write_bool(opb, arg)
    return readavailable(opb)
end

function getWireValue(arg::String)
    opb = PipeBuffer()
    ProtoBuf.write_string(opb, arg)
    return readavailable(opb)
end

function getWireValue(arg::Array{UInt8,1})
    opb = PipeBuffer()
    ProtoBuf.write_bytes(opb, arg)
    return readavailable(opb)
end

function getWireValue{T}(arg::Array{T, 1})
    opb = PipeBuffer()
    ProtoBuf.writeproto(opb, krpc.schema.List(items=map(getWireValue, arg)))
    return readavailable(opb)
end

function getWireValue{K,V}(arg::Dict{K,V})
    opb = PipeBuffer()
    op = Array{Array{UInt8,1},1}()
    for kv in arg
        k,v = kv
        push!(op, krpc.schema.DictionaryEntry(key=getWireValue(k), value=getWireValue(v)))
    end
    ProtoBuf.writeproto(opb, krpc.schema.Dictionary(entries=op))
    return readavailable(opb)
end

function getWireValue{T}(arg::Set{T})
    opb = PipeBuffer()
    ProtoBuf.writeproto(opb, krpc.schema.Set(items=map(getWireValue, arg)))
    return readavailable(opb)
end

function getWireValue(arg::Tuple)
    opb = PipeBuffer()
    ProtoBuf.writeproto(opb, krpc.schema.Tuple_(items=convert(Array{Array{UInt8,1},1}, collect(map(getWireValue, arg)))))
    return readavailable(opb)
end

function getWireValue(arg::kRPCTypes.Class)
    res = getWireValue(arg.handle)
    return res
end

function getWireValue(arg::kRPCTypes.Enum)
    return getWireValue(Remote.getEnumVal(arg))
end

function getWireValue(arg::krpc.schema.ProcedureCall)
    opb = PipeBuffer()
    ProtoBuf.writeproto(opb, arg)
    return readavailable(opb)
end

function getWireValue(arg::kStream)
    opb = PipeBuffer()
    ProtoBuf.writeproto(opb, krpc.schema.Stream(id=arg.id))
    return readavailable(opb)
end

function getJuliaValue(value::krpc.schema.Response, rtype::Type)
    return getJuliaValue(value.return_value, rtype)
end
function getJuliaValue{T<:kRPCTypes.Class}(value::Array{UInt8, 1}, rtype::Type{T})
    return rtype(ProtoBuf.read_varint(PipeBuffer(value), Int64))
end

function getJuliaValue(value::Array{UInt8, 1}, rtype::Void)
    return Void()
end

function getJuliaValue(value::Array{UInt8, 1}, rtype::Type{AbstractString})
    return ProtoBuf.read_string(PipeBuffer(value))
end

function getJuliaValue(value::Array{UInt8, 1}, rtype::Type{kStream})
    backing = readproto(PipeBuffer(value), krpc.schema.Stream())
    return kStream(backing.id)
end

function getJuliaValue(value::Array{UInt8, 1}, rtype::Union{Type{UInt32},Type{Int32},Type{UInt64},Type{Int64},Type{Float32},Type{Float64}})
    return ProtoBuf.read_fixed(PipeBuffer(value), rtype)
end

function getJuliaValue(value::Array{UInt8, 1}, rtype::Type{Bool})
    return ProtoBuf.read_bool(PipeBuffer(value))
end

function getJuliaValue(value::Array{UInt8, 1}, rtype::Type{Array{UInt8,1}})
    return ProtoBuf.read_bytes(PipeBuffer(value))
end

function getJuliaValue{T}(value::Array{UInt8, 1}, rtype::Type{Array{T,1}})
    res = readproto(PipeBuffer(value), krpc.schema.List())
    return T[getJuliaValue(item,T) for item in res.items]
end

function getJuliaValue{T <: (Tuple{Vararg{T,N} where T where N})}(value::Array{UInt8, 1}, rtype::Type{T})
    res = readproto(PipeBuffer(value), krpc.schema.Tuple_())
    return ([getJuliaValue(param[1],param[2]) for param in zip(res.items, rtype.parameters)]...)
end

function getJuliaValue{K,V}(value::Array{UInt8, 1}, rtype::Type{Dict{K,V}})
    res = readproto(PipeBuffer(value), krpc.schema.Dictionary())
    return Dict{K,V}(getJuliaValue(v.key,K) => getJuliaValue(v.value,V) for v in res.entries)
end

function getJuliaValue{T}(value::Array{UInt8, 1}, rtype::Type{Set{T}})
    res = readproto(PipeBuffer(value), krpc.schema.Set())
    return Set{T}(getJuliaValue(item,T) for item in res.items)
end

function getJuliaValue{T<:kRPCTypes.Class}(value::Array{UInt8, 1}, rtype::Type{Nullable{T}})
    res = ProtoBuf.read_varint(PipeBuffer(value), Int64)
    if res == 0
        return Nullable{T}()
    else
        return Nullable(T(res))
    end
end