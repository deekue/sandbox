#!/bin/bash

# abort this script on errors
set -euxo pipefail

whoami

cd /vagrant

make_certs_writable() (
	local certdir="/etc/docker/certs.d/$TINKERBELL_HOST_IP"
	sudo mkdir -p "$certdir"
	sudo chown -R "$USER" "$certdir"
)

secure_certs() (
	local certdir="/etc/docker/certs.d/$TINKERBELL_HOST_IP"
	sudo chown "root" "$certdir"
)

configure_vagrant_user() (
	echo -n "$TINKERBELL_REGISTRY_PASSWORD" |
		sudo -iu vagrant docker login \
			--username="$TINKERBELL_REGISTRY_USERNAME" \
			--password-stdin "$TINKERBELL_HOST_IP"
)

setup_nat() (
	iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
	iptables -A FORWARD -i eth0 -o eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
	iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
)

main() (
	export DEBIAN_FRONTEND=noninteractive

	if ! [[ -f ./.tink-env ]]; then
		./generate-env.sh eth1 > .tink-env
	fi

	# shellcheck disable=SC1091
	source ./.tink-env

	make_certs_writable

	./setup.sh

	if [[ ${TINKERBELL_CONFIGURE_NAT:=true} != "false" ]]; then
		setup_nat
	fi

	secure_certs
	configure_vagrant_user

	set +x # don't want the stderr output from xtrace messing with the post-setup-message
	[[ -f /tmp/post-setup-message ]] && cat /tmp/post-setup-message
)

main
