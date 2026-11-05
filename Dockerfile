# syntax=docker/dockerfile:1
FROM debian:13-slim

ARG APT_CACHER_NG_VERSION="*"
ARG APT_CACHER_NG_CONF_FILE="/etc/apt-cacher-ng/acng.conf"

ENV APT_CACHER_NG_CACHE_DIR=/var/cache/apt-cacher-ng \
    APT_CACHER_NG_LOG_DIR=/var/log/apt-cacher-ng \
    APT_CACHER_NG_CONFIG_DIR=/etc/apt-cacher-ng/user-config \
    APT_CACHER_NG_PID_DIR=/run/apt-cacher-ng \
    APT_CACHER_NG_USER=apt-cacher-ng

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends --no-install-suggests -y \
        apt-cacher-ng=${APT_CACHER_NG_VERSION} \
        ca-certificates \
        wget \
    && \
    sed 's/# ForeGround: 0/ForeGround: 1/' -i /etc/apt-cacher-ng/acng.conf && \
    sed 's/# PassThroughPattern:.*this would allow.*/PassThroughPattern: .*/' -i /etc/apt-cacher-ng/acng.conf && \
    apt-get full-upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# Changing configuration file of "apt-cacher-ng"
# Comment out some parameter fields (but keep them!)
RUN <<EOF
    disable_param() {
        local param="$1"
        sed -i -E "s/^([[:space:]]*${param}:)/# \1/" "${APT_CACHER_NG_CONF_FILE}"
    }

    disable_param "ExThreshold"
    disable_param "FollowIndexFileRemoval"
    disable_param "ForeGround"
    disable_param "VerboseLog"
    disable_param "DnsCacheSeconds"
    disable_param "DlMaxRetries"
EOF

# Inject overlaid parameters (at the end!)
RUN cat <<EOF >> ${APT_CACHER_NG_CONF_FILE}
# begin of config
ExThreshold: 30
FollowIndexFileRemoval: 0
ForeGround: 1
VerboseLog: 1
DnsCacheSeconds: 360
DlMaxRetries: 20
# end of config
EOF

RUN echo "***** ${APT_CACHER_NG_CONF_FILE} *****" && \
    cat ${APT_CACHER_NG_CONF_FILE}

COPY --chmod=755 <<'EOF' /sbin/entrypoint.sh
#!/bin/bash
set -e
# Creates pid dir
install -d -m 0755 \
  -o "${APT_CACHER_NG_USER}" \
  -g "${APT_CACHER_NG_USER}" \
  "${APT_CACHER_NG_PID_DIR}"

# Creates cache dir
install -d -m 0755 \
  -o "${APT_CACHER_NG_USER}" \
  -g root \
  "${APT_CACHER_NG_CACHE_DIR}"

# Creates log dir
install -d -m 0755 \
  -o "${APT_CACHER_NG_USER}" \
  -g "${APT_CACHER_NG_USER}" \
  "${APT_CACHER_NG_LOG_DIR}"

# From https://github.com/sameersbn/docker-apt-cacher-ng/pull/64/files courtesy of jack60612
# if user config directory was mounted / exists copy files to main apt-cacher-ng directory
if [ -d "$APT_CACHER_NG_CONFIG_DIR" ]; then
  cp -r "${APT_CACHER_NG_CONFIG_DIR}"/. /etc/apt-cacher-ng/
fi

# Arguments to be passed to apt-cacher-ng
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$*"
  set --
elif [[ ${1} == apt-cacher-ng || ${1} == $(command -v apt-cacher-ng) ]]; then
  EXTRA_ARGS="${*:2}"
  set --
fi

# Function to tail log files once they exist
tail_logs() {
  local log_files=(
    "${APT_CACHER_NG_LOG_DIR}/apt-cacher.log"
    "${APT_CACHER_NG_LOG_DIR}/apt-cacher.err"
    "${APT_CACHER_NG_LOG_DIR}/apt-cacher.dbg"
  )

  # Wait for log files to be created, then tail them
  while true; do
    local existing_files=()
    for file in "${log_files[@]}"; do
      if [[ -f "$file" ]]; then
        existing_files+=("$file")
      fi
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
      tail -f "${existing_files[@]}"
      break
    fi

    sleep 1
  done
}

# The default behaviour is to launch apt-cacher-ng
if [[ -z ${1} ]]; then
  # Start apt-cacher-ng in background
  start-stop-daemon \
    --start \
    --chuid "${APT_CACHER_NG_USER}":"${APT_CACHER_NG_USER}" \
    --exec "$(command -v apt-cacher-ng)" \
    -- \
    -c /etc/apt-cacher-ng "${EXTRA_ARGS}" &

  # Tail the log files
  tail_logs
else
  exec "$@"
fi
EOF

EXPOSE 3142/tcp

HEALTHCHECK --interval=10s --timeout=2s --retries=3 \
    CMD wget -q -t1 -O /dev/null http://localhost:3142/acng-report.html || exit 1

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/usr/sbin/apt-cacher-ng"]

