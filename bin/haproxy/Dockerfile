FROM alpine:3.20

# runtime dependencies
RUN set -eux; \
	apk add --no-cache \
		ca-certificates \
	;

RUN set -eux; \
	addgroup --gid 99 --system haproxy; \
	adduser \
		--disabled-password \
		--home /var/lib/haproxy \
		--ingroup haproxy \
		--no-create-home \
		--system \
		--uid 99 \
		haproxy \
	; \
	mkdir /var/lib/haproxy; \
	chown haproxy:haproxy /var/lib/haproxy

ENV HAPROXY_VERSION=2.9.5
ENV HAPROXY_URL=https://www.haproxy.org/download/2.9/src/haproxy-2.9.5.tar.gz
ENV HAPROXY_SHA256=cd18c902e7692fbd4870a132d78baef96753547d492617a2a9e0f922d2fc850e

# choose Lua version if needed (только если нужна поддержка lua)
ARG LUA_VERSION=5.4

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		gcc \
		libc-dev \
		linux-headers \
		lua${LUA_VERSION}-dev \
		make \
		openssl \
		openssl-dev \
		pcre2-dev \
		readline-dev \
		tar \
		wget \
	; \
	wget -O haproxy.tar.gz "$HAPROXY_URL"; \
	echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c; \
	mkdir -p /usr/src/haproxy; \
	tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1; \
	rm haproxy.tar.gz; \
	\
	# Собираем с поддержкой QUIC/UDP
	makeOpts=" \
		TARGET=linux-musl \
		USE_GETADDRINFO=1 \
		USE_LUA=1 LUA_INC=/usr/include/lua${LUA_VERSION} LUA_LIB=/usr/lib/lua${LUA_VERSION} \
		USE_OPENSSL=1 \
		USE_PCRE2=1 USE_PCRE2_JIT=1 \
		USE_PROMEX=1 \
		USE_QUIC=1 \
	"; \
	nproc="$(getconf _NPROCESSORS_ONLN)"; \
	eval "make -C /usr/src/haproxy -j '$nproc' all $makeOpts"; \
	eval "make -C /usr/src/haproxy install-bin $makeOpts"; \
	mkdir -p /usr/local/etc/haproxy; \
	cp -R /usr/src/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors; \
	rm -rf /usr/src/haproxy; \
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-network --virtual .haproxy-rundeps $runDeps; \
	apk del --no-network .build-deps; \
	haproxy -v

STOPSIGNAL SIGUSR1

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

USER haproxy

WORKDIR /var/lib/haproxy

CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
