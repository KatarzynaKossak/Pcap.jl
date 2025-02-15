export EthHdr, IpFlags, IpHdr,
       UdpHdr, TcpFlags, TcpHdr,
       IcmpHdr, DecPkt, decode_pkt

mutable struct EthHdr
    dest_mac::AbstractString
    src_mac::AbstractString
    ptype::UInt16
    EthHdr() = new("","",0)
end # struct of EthHdr

mutable struct IpFlags
    reserved::Bool
    dont_frag::Bool
    more_frags::Bool
    IpFlags() = new(false,false,false)
end # struct of  IpFlags

mutable struct IpHdr
    version::UInt8
    length::UInt8
    services::UInt8
    totlen::UInt16
    id::UInt16
    flags::IpFlags
    frag_offset::UInt16
    ttl::UInt8
    protocol::UInt8
    checksum::Bool
    src_ip::AbstractString
    dest_ip::AbstractString
    IpHdr() = new(0,0,0,0,0,IpFlags(),0,0,0,false,"","")
end # struct of  IpHdr

mutable struct TcpFlags
    reserved::Bool
    nonce::Bool
    cwr::Bool
    ecn::Bool
    urgent::Bool
    ack::Bool
    push::Bool
    reset::Bool
    syn::Bool
    fin::Bool
    TcpFlags() = new(false,false,false,false,false,
                     false,false,false,false,false)
end # struct of  TcpFlags

mutable struct TcpHdr
    src_port::UInt16
    dest_port::UInt16
    seq::UInt32
    ack::UInt32
    offset::UInt8
    flags::TcpFlags
    window::UInt16
    checksum::UInt16
    uptr::UInt16
    data::Vector{UInt8}
    TcpHdr() = new(0,0,0,0,0,TcpFlags(),0,0,0, Vector{UInt8}(0))
end # struct of  TcpHdr

mutable struct UdpHdr
    src_port::UInt16
    dest_port::UInt16
    length::UInt16
    checksum::UInt16
    data::Vector{UInt8}
    UdpHdr() = new(0,0,0,0,Vector{UInt8}())
end # struct of  UdpHdr

mutable struct IcmpHdr
    ptype::UInt8
    code::UInt8
    checksum::UInt16
    identifier::UInt16
    seqno::UInt16
    IcmpHdr() = new(0,0,0,0,0)
end # struct of  IcmpHdr

mutable struct DecPkt
    datalink::EthHdr
    network::IpHdr
    protocol::Any
    DecPkt() = new(EthHdr(), IpHdr(), nothing)
end # struct of  DecPkt



@inline function getindex_he(::Type{T}, b::Vector{UInt8}, i) where {T}
    # r: getindex_he When 0.4 support is dropped, add @boundscheck
    @boundscheck checkbounds(b, i + sizeof(T) - 1)
    return unsafe_load(Ptr{T}(pointer(b, i)))
    
end 

@inline function getindex_be(::Type{T}, b::Vector{UInt8}, i) where {T} 
    @boundscheck checkbounds(b, i + sizeof(T) - 1)
    return hton(getindex_he(T, b, i))

end   


#----------
# decode ethernet header
#----------
hex(n) = string(n, base=16, pad=2)

function decode_eth_hdr(d::Array{UInt8})
    eh = EthHdr()                   
    eh.dest_mac = join(hex.(d[1:6]), ":")  # apply hex to first 6 elements and join result with ":"
    eh.src_mac  = join(hex.(d[7:12]), ":")  # do it for next 6 elements
    eh.ptype    = getindex_be(UInt16, d, 13)
    eh
end # function decode_eth_hdr

#----------
# calculate IP checksum
#----------
function ip_checksum(buf::Array{UInt8})
    sum::UInt64 = 0
    for i in 1:2:length(buf)
        pair = getindex_he(UInt16, buf, i)
        sum += pair
        if (sum & 0x80000000) != 0
            sum = (sum & 0xFFFF) + (sum >> 16)
        end
    end

    while ((sum >> 16) != 0)
        sum = (sum & 0xFFFF) + (sum >> 16)
    end
    ~sum
end # function ip_checksum

#----------
# decode IP header
#----------
function decode_ip_hdr(d::Array{UInt8})
    iph = IpHdr()
    iph.version     = (d[1] & 0xf0) >> 4
    iph.length      = (d[1] & 0x0f) * 4
    if ip_checksum(d[1:iph.length]) == 0xFFFFFFFFFFFF0000
        iph.checksum = true
    end
    iph.services    = d[2]
    iph.totlen      = getindex_be(UInt16, d, 3)
    iph.id          = getindex_be(UInt16, d, 5)

    # set flags
    flags = IpFlags()
    flags.reserved   = (d[7] & (1 << 7)) > 0
    flags.dont_frag  = (d[7] & (1 << 6)) > 0
    flags.more_frags = (d[7] & (1 << 5)) > 0
    iph.flags        = flags

    iph.frag_offset = getindex_be(UInt16, d, 7) & 0x7ff
    iph.ttl         = d[9]
    iph.protocol    = d[10]
    iph.src_ip      = string(Int(d[13]), ".", Int(d[14]), ".", Int(d[15]), ".", Int(d[16]))
    iph.dest_ip     = string(Int(d[17]), ".", Int(d[18]), ".", Int(d[19]), ".", Int(d[20]))
    iph
end # function decode_ip_hdr

#----------
# decode TCP header
#----------
function decode_tcp_hdr(d::Array{UInt8})
    tcph = TcpHdr()
    tcph.src_port  = getindex_be(UInt16, d, 1)
    tcph.dest_port = getindex_be(UInt16, d, 3)
    tcph.seq       = getindex_be(UInt32, d, 5)
    tcph.ack       = getindex_be(UInt32, d, 9)
    tcph.offset    = (d[13] & 0xf0) >> 4

    # set flags
    flags = TcpFlags()
    flags.reserved = ((d[13] & 0x0e) >> 1) > 0
    flags.nonce    = (d[13] & 1) > 0
    flags.cwr      = (d[14] & (1 << 7)) > 0
    flags.ecn      = (d[14] & (1 << 6)) > 0
    flags.urgent   = (d[14] & (1 << 5)) > 0
    flags.ack      = (d[14] & (1 << 4)) > 0
    flags.push     = (d[14] & (1 << 3)) > 0
    flags.reset    = (d[14] & (1 << 2)) > 0
    flags.syn      = (d[14] & (1 << 1)) > 0
    flags.fin      = (d[14] & 1) > 0
    tcph.flags     = flags

    tcph.window    = getindex_be(UInt16, d, 15)
    tcph.checksum  = getindex_be(UInt16, d, 17)
    tcph.uptr      = getindex_be(UInt16, d, 19)
    tcph.data      = d[tcph.offset * 4 + 1:end]
    tcph
end # function decode_tcp_hdr

#----------
# decode UDP header
#----------
function decode_udp_hdr(d::Array{UInt8})
    udph = UdpHdr()
    udph.src_port  = getindex_be(UInt16, d, 1)
    udph.dest_port = getindex_be(UInt16, d, 3)
    udph.length    = getindex_be(UInt16, d, 5)
    udph.checksum  = getindex_be(UInt16, d, 7)
    udph.data      = d[9:end]
    udph
end # function decode_udp_hdr

#----------
# decode ICMP header
#----------
function decode_icmp_hdr(d::Array{UInt8})
    icmph = IcmpHdr()
    icmph.ptype      = d[1]
    icmph.code       = d[2]
    icmph.checksum   = getindex_be(UInt16, d, 3)
    icmph.identifier = getindex_be(UInt16, d, 5)
    icmph.seqno      = getindex_be(UInt16, d, 7)
    icmph
end # function decode_icmp_hdr

#----------
# decode ethernet packet
#----------
function decode_pkt(pkt::Array{UInt8})
    decoded           = DecPkt()
    decoded.datalink  = decode_eth_hdr(pkt)
    iphdr             = decode_ip_hdr(pkt[15:end])
    decoded.network   = iphdr

    proto = nothing
    if (iphdr.protocol == 1)
        proto = decode_icmp_hdr(pkt[15 + iphdr.length:end])
    elseif (iphdr.protocol == 6)
        proto = decode_tcp_hdr(pkt[15 + iphdr.length:end])
    elseif (iphdr.protocol == 17)
        proto = decode_udp_hdr(pkt[15 + iphdr.length:end])
    end

    decoded.protocol = proto
    decoded
end # function decode_pkt
