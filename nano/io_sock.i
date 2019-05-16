

/* -------------------------------------------------------------------------- */
#define IO_CON_BUFFER_SIZE (0x1000)


typedef struct io_tcp_pipe tcp_pipe_t;

/* -------------------------------------------------------------------------- */
struct io_tcp_pipe {
	io_stream_t stream;
	uint32_t remote_ip;
	uint32_t remote_port;
	io_buf_t out;
	int connecting;
	tcp_pipe_t *pipe;
};


/* -------------------------------------------------------------------------- */
static void tcp_pipe_free(io_stream_t *stream)
{
	tcp_pipe_t *p = (tcp_pipe_t *)stream;
	if (p->pipe) {
		io_stream_t *ps = &p->pipe->stream;
		p->pipe = NULL;
		io_stream_free(ps);
	}
	io_buf_free(&p->out);
}

/* -------------------------------------------------------------------------- */
static void tcp_pipe_event_handler(io_stream_t *stream, int events)
{
	tcp_pipe_t *p = (tcp_pipe_t *)stream;
	if (events & POLLOUT) {
		if (io_buf_send(&p->out, stream->fd) < 0) {
			if (errno == ECONNRESET || errno == ENOTCONN || errno == EPIPE)
				tcp_pipe_free(stream);
		}
	}
	if (events & POLLIN) {
		if (p->connecting) {
			int err = 0;
			socklen_t len = sizeof (int);
			if (getsockopt(stream->fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0) {
				errno = err;
				syslog(LOG_ERR, "connect to %s:%d failed (%m)", ipv4_itoa(p->remote_ip), p->remote_port);
				tcp_pipe_free(stream);
			} else {
				if (!err)
					p->connecting = 0;
			}
		}
		if (p->pipe) {
			if (!io_buf_recv(&p->pipe->out, stream->fd)) {
				tcp_pipe_free(stream);
			} else {
				tcp_pipe_event_handler(&p->pipe->stream, POLLOUT);
			}
		}
	}
}

/* -------------------------------------------------------------------------- */
static const io_stream_ops_t tcp_pipe_ops = {
	.free = tcp_pipe_free,
	.idle = NULL,
	.event = tcp_pipe_event_handler
};


/* -------------------------------------------------------------------------- */
static tcp_pipe_t *tcp_pipe_create(int sock, uint32_t ip, uint32_t port)
{
	tcp_pipe_t *t = (tcp_pipe_t *)calloc(1, sizeof (tcp_pipe_t));

	t->remote_ip   = ip;
	t->remote_port = port;

	//t->connecting = 0;
	//t->pipe = NULL;

	io_buf_init(&t->out);

	io_stream_init(&t->stream, sock, POLLIN|POLLOUT, &tcp_pipe_ops);
	return t;
}


/* -------------------------------------------------------------------------- */
static void tcp_pipe_link(tcp_pipe_t *list, tcp_pipe_t *conn)
{
	list->pipe = conn;
	conn->pipe = list;
}




/* -------------------------------------------------------------------------- */
static void tcp_pipe_server_event_handler(io_stream_t *stream, int events)
{
	tcp_pipe_server_t *p = (tcp_pipe_server_t *)stream;

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;

	socklen_t addrlen = sizeof addr;

	int sock = accept4(stream->fd, (struct sockaddr *)&addr, &addrlen, SOCK_NONBLOCK);
	if (sock < 0) {
		syslog(LOG_ERR, "fail to accept connection (%m)");
		return ;
	}
	tcp_pipe_t *list = tcp_pipe_create(sock, ntohl(addr.sin_addr.s_addr), ntohs(addr.sin_port));

	list->connecting = 0;

	addr.sin_port = htons(p->host_port);
	addr.sin_addr.s_addr = p->host_ip ? htonl(p->host_ip) : htonl(INADDR_ANY);

	sock = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);

	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0 && errno != EINPROGRESS) {
		syslog(LOG_ERR, "fail to connect to %s:%d (%m)", ipv4_itoa(p->host_ip), p->host_port);
		io_stream_free(&list->stream);
		close(sock);
		return ;
	}

	tcp_pipe_t *con = tcp_pipe_create(sock, p->host_ip, p->host_port);
	con->connecting = 1;

	tcp_pipe_link(list, con);
}

/* -------------------------------------------------------------------------- */
static const io_stream_ops_t tcp_pipe_server_ops = {
	.free = NULL,
	.idle = NULL,
	.event = tcp_pipe_server_event_handler
};

/* -------------------------------------------------------------------------- */
tcp_pipe_server_t *tcp_pipe_server_create(uint32_t listen_ip, uint32_t listen_port, char const *iface, int listen_queue, uint32_t host_ip, uint32_t host_port)
{
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(listen_port);
	addr.sin_addr.s_addr = listen_ip ? htonl(listen_ip) : htonl(INADDR_ANY);

	int sock = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);

	if (iface)
		if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, iface, (socklen_t)strlen(iface) + 1) < 0) {
			syslog(LOG_ERR, "fail to bind listen socket to interface '%s' (%m)", iface);
			close(sock);
			return NULL;
		}

	if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(sock, listen_queue) < 0) {
		syslog(LOG_ERR, "fail to bind listen socket to address '%s:%d' (%m)", ipv4_itoa(listen_ip), listen_port);
		close(sock);
		return NULL;
	}

	tcp_pipe_server_t *s = (tcp_pipe_server_t *)calloc(1, sizeof (tcp_pipe_server_t));

	if (iface)
		snprintf(s->iface, sizeof s->iface, "%s", iface);

	s->host_ip   = host_ip;
	s->host_port = host_port;

	io_stream_init(&s->stream, sock, POLLIN, &tcp_pipe_server_ops);

	return s;
}


