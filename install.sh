#!/bin/bash

set -eu

main() {
  need_cmd hab
  need_cmd openssl
  need_cmd wget

  install_docker
  make_work_dirs
  clone_and_unpack
  info "Installation Complete"
  generate_passwd
}

docker_systemd_conf(){
  cat <<EOF > /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service
Wants=network-online.target
Requires=docker.socket
[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/bin/dockerd -H fd://
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=1048576
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/docker.socket
[Unit]
Description=Docker Socket for the API
PartOf=docker.service
[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker
[Install]
WantedBy=sockets.target
EOF

#   mkdir -p /etc/systemd/system/docker.service.d

#   cat <<EOF > /etc/systemd/system/docker.service.d/proxy.conf
# [Service]
# Environment="HTTP_PROXY=http://proxyvipfmcc.nb.ford.com:83" "HTTPS_PROXY=http://proxyvipfmcc.nb.ford.com:83" "NO_PROXY=localhost,127.0.0.1,.ford.com,19.0.0.0/8,136.1.0.0/16,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.sock,.dev,chef-prod-smk-01.fmcc.ford.com,aplvc10.hplab1.ford.com,aplvc02.qa.hplab1.ford.com,ito000604.fhc.ford.com"
# EOF

  systemctl daemon-reload
  systemctl enable docker
  systemctl enable docker.socket
  systemctl restart docker
}

docker_groupadd(){
  if ! grep -q "^docker:" /etc/group ; then
    groupadd docker
  fi
  if ! id -u hab >/dev/null 2>&1 ; then
    useradd hab
  fi
  usermod -aG docker hab
}

install_docker() {
  hab pkg install core/docker -bf
  # hab pkg install core/docker-compose -bf
  docker_systemd_conf
  docker_groupadd
}

make_work_dirs() {
  mkdir -p /opt/monitoring
}

clone_and_unpack() {
  pushd /opt/monitoring
  wget -O - https://github.com/gscho/prometheus-grafana/tarball/master | tar --strip-components=1 -zx
  popd
  info "unpacked prometheus-grafana to /opt/monitoring"
}

generate_passwd() {
  local _pw
  _pw=$(openssl rand -base64 32)
  cat <<EOF > /opt/monitoring/grafana/config.monitoring
GF_SECURITY_ADMIN_PASSWORD=$_pw
GF_USERS_ALLOW_SIGN_UP=false

EOF
  echo "PASSWORD=${_pw}"
}

need_cmd() {
  if ! command -v "$1" > /dev/null 2>&1; then
    exit_with "Required command '$1' not found on PATH" 127
  fi
}

info() {
  echo "INFO prometheus-grafana: $1"
}

warn() {
  echo "WARN prometheus-grafana: $1" >&2
}

exit_with() {
  warn "$1"
  exit "${2:-10}"
}

main || exit 99
