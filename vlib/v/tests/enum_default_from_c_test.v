import net

const suppress_unused_warning = net.infinite_timeout

// Note the order here is deliberately changed compared to net.SocketType,
// so C.SOCK_SEQPACKET will be used first, and C.SOCK_STREAM last.
// All 3 should be != 0 on all platforms, and their values will come from the C headers
enum MyEnumFromC {
	a = C.SOCK_SEQPACKET
	b = C.SOCK_DGRAM
	c = C.SOCK_STREAM
}

const seq_value = MyEnumFromC.a

const udp_value = MyEnumFromC.b

const tcp_value = MyEnumFromC.c

//
enum Abc {
	a = 999
	b
	c
}

const zzz = Abc.b

fn test_default_enum_values() {
	assert int(tcp_value) != 0
	assert int(seq_value) != 0
	assert int(udp_value) != 0
	assert int(zzz) == 1000
}
