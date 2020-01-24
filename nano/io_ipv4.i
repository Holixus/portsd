/* ------------------------------------------------------------------------ */
static char *bput(char *p, unsigned int byte)
{
	byte &= 255;
	if (byte >= 100) {
		*p++ = (char)(byte / 100 + '0');
		byte %= 100;
		goto _2;
	}
	if (byte >= 10) {
_2:
		*p++ = (char)('0' + byte / 10);
		byte %= 10;
	}
	*p++ = (char)('0' + byte);
	return p;
}

/* ------------------------------------------------------------------------ */
static char *ipv4_itostr(char *p, unsigned int ip)
{
	p = bput(p, ip >> 24);
	*p++ = '.';
	p = bput(p, ip >> 16);
	*p++ = '.';
	p = bput(p, ip >> 8);
	*p++ = '.';
	p = bput(p, ip);
	*p = 0;
	return p;
}

enum { IP_BUF_SIZE = 32 };

/* ------------------------------------------------------------------------ */
static char *_getIpBuf()
{
	static char buf[8][IP_BUF_SIZE];
	static int index = 0;
	return buf[index++ & 7];
}

/* ------------------------------------------------------------------------ */
char const *ipv4_itoa(unsigned int num)
{
	char *buf = _getIpBuf();
	ipv4_itostr(buf, num);
	return buf;
}

/* ------------------------------------------------------------------------ */
unsigned int ipv4_atoi(char const *ip, char const **after)
{
	unsigned int num = 0, c = 4;
	goto _start;
	do {
		if (*ip != '.')
			return 0;
		++ip;
_start:;
		char const *next;
		unsigned long n = strtoul(ip, (char **)&next, 10);
		if (next == ip || n >= 256)
			return 0;
		ip = next;
		num = num << 8 | (unsigned int)n;
	} while (--c);

	if (after)
		*after = ip;

	return num;
}


