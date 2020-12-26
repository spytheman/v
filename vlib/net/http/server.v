module http

import net

type Header = map[string]string

interface ResponseWriter {
	header() Header
	write(data []byte) ?int
	write_status_header(status Status)
}

interface Handler {
	serve(writer ResponseWriter, req &Request)
}

interface Server {
	listen_and_serve(where string, handler Handler)?
}

struct SimpleServer {
pub mut:
	where string
	port u16
	listener net.TcpListener
	handler Handler
}

pub fn (mut server SimpleServer) listen_and_serve(where string, handler Handler) ? {
	server.where = where
	server.handler = handler
	if where.contains(':') {
		server.port = where.all_after(':').u16()
	} else {
		server.port = where.u16()
	}
	if server.port == 0 {
		return error('invalid port')
	}
	server.listener = net.listen_tcp(server.port)?
	for {
		mut conn := server.listener.accept()?
		server.new_connection(mut conn)
	}
}

pub fn (mut server SimpleServer) new_connection(mut con net.TcpConn) {
	eprintln('> new con: $con')
}
