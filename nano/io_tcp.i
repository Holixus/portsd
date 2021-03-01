

/* -------------------------------------------------------------------------- */
#define IO_CON_BUFFER_SIZE (0x1000)


/* -------------------------------------------------------------------------- */
typedef
struct io_tcp {
	io_stream_t stream;
	uint32_t remote_ip;
	uint32_t remote_port;
	io_buf_t out;
} io_tcp_t;


typedef struct io_tcp_listen io_tcp_listen_t;

typedef
void (*accept_handler_t)(io_tcp_listen_t *self, int sock, uint32_t remote_ip, uint32_t remote_port);

/* -------------------------------------------------------------------------- */
struct io_tcp_listen {
	io_stream_t stream;
	uint32_t ip;
	uint32_t port;
	char iface[32];
	accept_handler_t accept_handler;
};


/* -------------------------------------------------------------------------- */
typedef
struct tcp_listen_conf {
	uint32_t ip;
	uint32_t port;
	int queue_size;
	char const *iface;
} io_tcp_listen_conf_t;

/* -------------------------------------------------------------------------- */
static void io_tcp_free(io_stream_t *stream)
{
	io_tcp_t *p = (io_tcp_t *)stream;
	io_buf_free(&p->out);
}

/* -------------------------------------------------------------------------- */
static int io_tcp_write(io_stream_t *stream, char *data, size_t size)
{
	io_tcp_t *p = (io_tcp_t *)stream;

	if (io_buf_is_empty(&p->out)) {
		ssize_t sent = send(stream->fd, data, size, 0);
		if (sent < 0)
			return -1;
		if (sent == size)
			return size;
		data += sent;
		size -= sent;
	}
	if (size)
		stream->events |= POLLOUT;
	return io_buf_write(&p->out, data, size);
}

/* -------------------------------------------------------------------------- */
static int io_tcp_writef(io_stream_t *stream, char const *fmt, ...) __attribute__ ((format (printf, 2, 3)));

static int io_tcp_writef(io_stream_t *stream, char const *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	char msg[256];
	size_t len = (size_t)vsnprintf(msg, sizeof msg, fmt, ap);
	int r = io_tcp_write(stream, msg, len);
	va_end(ap);
	return r;
}

/* -------------------------------------------------------------------------- */
static void io_tcp_event_handler(io_stream_t *stream, int events)
{
	io_tcp_t *p = (io_tcp_t *)stream;
	if (events & POLLOUT) {
		if (io_buf_send(&p->out, stream->fd) < 0) {
			if (errno == ECONNRESET || errno == ENOTCONN || errno == EPIPE)
				io_stream_free(stream);
		} else
			if (io_buf_is_empty(&p->out))
				stream->events &= ~POLLOUT;
	}
}

/* -------------------------------------------------------------------------- */
static const io_stream_ops_t io_tcp_ops = {
	.free = io_tcp_free,
	.idle = NULL,
	.event = io_tcp_event_handler
};


/* -------------------------------------------------------------------------- */
static io_tcp_t *io_tcp_create(int sock, uint32_t ip, uint32_t port, io_stream_ops_t const *ops)
{
	io_tcp_t *t = (io_tcp_t *)calloc(1, sizeof (io_tcp_t));

	t->remote_ip   = ip;
	t->remote_port = port;

	io_buf_init(&t->out);

	io_stream_init(&t->stream, sock, POLLIN|POLLOUT, ops ?: &io_tcp_ops);
	return t;
}



/* -------------------------------------------------------------------------- */
static int io_tcp_listen(uint32_t ip, uint32_t port, char const *iface, int queue_size)
{
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = ip ? htonl(ip) : htonl(INADDR_ANY);

	int sock = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);

	if (iface)
		if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, iface, (socklen_t)strlen(iface) + 1) < 0) {
			syslog(LOG_ERR, "fail to bind listen socket to interface '%s' (%m)", iface);
			close(sock);
			return -1;
		}

	if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(sock, queue_size) < 0) {
		syslog(LOG_ERR, "fail to bind listen socket to address '%s:%d' (%m)", ipv4_itoa(ip), port);
		close(sock);
		return -1;
	}

	return sock;
}

/* -------------------------------------------------------------------------- */
static int io_tcp_accept(io_stream_t *stream, uint32_t *remote_ip, uint32_t *remote_port)
{
	//io_tcp_listen_t *p = (io_tcp_listen_t *)stream;

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;

	socklen_t addrlen = sizeof addr;

	int sock = accept4(stream->fd, (struct sockaddr *)&addr, &addrlen, SOCK_NONBLOCK);
	if (sock < 0) {
		syslog(LOG_ERR, "failed to accept connection (%m)");
		return -1;
	}
	if (remote_ip)
		*remote_ip = ntohl(addr.sin_addr.s_addr);
	if (remote_port)
		*remote_port = ntohs(addr.sin_port);
	return sock;
}


/* -------------------------------------------------------------------------- */
static int io_tcp_connect(uint32_t remote_ip, uint32_t remote_port, char const *iface)
{
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;

	addr.sin_port = htons(remote_port);
	addr.sin_addr.s_addr = remote_ip ? htonl(remote_ip) : htonl(INADDR_ANY);

	int sock = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
	if (sock < 0) {
		syslog(LOG_ERR, "failed to create socket (%m)");
		return -1;
	}

	if (iface)
		if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, iface, (socklen_t)strlen(iface) + 1) < 0) {
			syslog(LOG_ERR, "failed to bind socket to interface '%s' (%m)", iface);
			close(sock);
			return -1;
		}

	if (connect(sock, (struct sockaddr *)&addr, sizeof addr) < 0 && errno != EINPROGRESS) {
		syslog(LOG_ERR, "failed to connect to %s:%d (%m)", ipv4_itoa(remote_ip), remote_port);
		close(sock);
		return -1;
	}

	return sock;
}


/* -------------------------------------------------------------------------- */
static void io_tcp_listen_event_handler(io_stream_t *stream, int events)
{
	io_tcp_listen_t *p = (io_tcp_listen_t *)stream;

	uint32_t ip, port;
	int sock = io_tcp_accept(stream, &ip, &port);
	if (sock >= 0)
		p->accept_handler(p, sock, ip, port);
}

/* -------------------------------------------------------------------------- */
static const io_stream_ops_t io_tcp_listen_ops = {
	.free = NULL,
	.idle = NULL,
	.event = io_tcp_listen_event_handler
};

/* -------------------------------------------------------------------------- */
static io_tcp_listen_t *io_tcp_listen_create(io_tcp_listen_conf_t *conf, accept_handler_t handler)
{
	int sock = io_tcp_listen(conf->ip, conf->port, conf->iface, conf->queue_size);
	if (sock < 0)
		return NULL;

	io_tcp_listen_t *self = (io_tcp_listen_t *)calloc(1, sizeof (io_tcp_listen_t));

	if (conf->iface)
		snprintf(self->iface, sizeof self->iface, "%s", conf->iface);

	self->ip   = conf->ip;
	self->port = conf->port;

	self->accept_handler = handler;

	io_stream_init(&self->stream, sock, POLLIN, &io_tcp_listen_ops);
	return self;
}


