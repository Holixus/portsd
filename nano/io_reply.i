

/* -------------------------------------------------------------------------- */
#define IO_CON_BUFFER_SIZE (0x1000)


typedef struct io_tcp_reply tcp_reply_t;

/* -------------------------------------------------------------------------- */
struct io_tcp_reply {
	io_tcp_t tcp;
	char request[200];
	char *end;
	io_tcp_listen_t *up;
};


/* -------------------------------------------------------------------------- */
static void tcp_reply_free(io_stream_t *stream)
{
	io_tcp_free(stream);
	tcp_reply_t *p = (tcp_reply_t *)stream;
	p->up = NULL;
}


/* -------------------------------------------------------------------------- */
static void tcp_reply_cmd(tcp_reply_t *self, char *cmd)
{
	int port = self->up->port;
	syslog(LOG_NOTICE, "<%d> cmd: '%s'", self->up->port, cmd);
	if (!strcmp(cmd, "quit")) {
		io_tcp_writef(&self->tcp.stream, "%d: bye!\r\n", port);
		io_stream_free(&self->tcp.stream);
		syslog(LOG_NOTICE, "<%d> closed", port);
		return ;
	} else {
		io_tcp_writef(&self->tcp.stream, "%d: unknown command: '%s'\r\n", self->up->port, cmd);
	}
}


/* -------------------------------------------------------------------------- */
static void tcp_reply_event_handler(io_stream_t *stream, int events)
{
	io_tcp_event_handler(stream, events);

	tcp_reply_t *p = (tcp_reply_t *)stream;
	if (events & POLLIN) {
		size_t to_recv = (sizeof p->request) - (unsigned)(p->end - p->request);
		ssize_t len;
		do {
			len = recv(stream->fd, p->end, to_recv, 0);
		} while (len < 0 && errno == EINTR);
		if (len < 0) {
			syslog(LOG_ERR, "failed to recv (%m)");
		} else
			if (!len) {
				int port = p->up->port;
				io_stream_free(stream); // end of connection
				syslog(LOG_NOTICE, "<%d> closed", port);
			} else {
				char *cmd = p->request, *data = p->end, *lf, *end = p->end + len;

				while (end > data && (lf = (char *)memchr(data, '\n', (unsigned)(end - data)))) {
					*lf++ = 0;
					char *cr = memchr(cmd, '\r', (unsigned)(lf - cmd));
					if (cr)
						*cr = 0;
					tcp_reply_cmd(p, cmd);
					data = cmd = p->end = lf;
				}
				if (end > data) {
					memmove(p->request, data, (unsigned)(end - data));
					p->end = p->request + (unsigned)(end - data);
				} else {
					p->end = p->request;
				}
			}
	}
}


/* -------------------------------------------------------------------------- */
static const io_stream_ops_t tcp_reply_ops = {
	.free = tcp_reply_free,
	.idle = NULL,
	.event = tcp_reply_event_handler
};


/* -------------------------------------------------------------------------- */
static tcp_reply_t *tcp_reply_create(io_tcp_listen_t *up, int sock, uint32_t ip, uint32_t port)
{
	tcp_reply_t *t = (tcp_reply_t *)calloc(1, sizeof (tcp_reply_t));

	t->tcp.remote_ip   = ip;
	t->tcp.remote_port = port;
	t->up  = up;

	t->end = t->request;

	io_buf_init(&t->tcp.out);

	io_stream_init(&t->tcp.stream, sock, POLLIN|POLLOUT, &tcp_reply_ops);

	io_tcp_writef(&t->tcp.stream, "%d: hello, %s:%d!\r\n", up->port, ipv4_itoa(ip), port);
	return t;
}




/* -------------------------------------------------------------------------- */
static void tcp_reply_accept(io_tcp_listen_t *self, int sock, uint32_t remote_ip, uint32_t remote_port)
{
	syslog(LOG_NOTICE, "<%d> accept: '%s:%d'", self->port, ipv4_itoa(remote_ip), remote_port);
	/*tcp_reply_t *reply = */tcp_reply_create(self, sock, remote_ip, remote_port);
}

/* -------------------------------------------------------------------------- */
int tcp_reply_server_create(uint32_t ip, uint32_t port, char const *iface, int queue_size)
{
	io_tcp_listen_conf_t conf = {
		.ip = ip, .port = port,
		.queue_size = queue_size ?: 32,
		.iface = iface
	};
	//syslog(LOG_NOTICE, "listen: '%s:%d'", ipv4_itoa(ip), port);
	/*io_tcp_listen_t *self = */io_tcp_listen_create(&conf, tcp_reply_accept);
	return 0;
}


