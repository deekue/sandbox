#!/usr/bin/env bash

# stops the execution if a command or pipeline has an error
set -eu

if command -v tput >/dev/null && tput setaf 1 >/dev/null 2>&1; then
	# color codes
	RED="$(tput setaf 1)"
	RESET="$(tput sgr0)"
fi

ERR="${RED:-}ERROR:${RESET:-}"

source ./current_versions.sh

err() (
	if [[ -z ${1:-} ]]; then
		cat >&2
	else
		echo "$ERR " "$@" >&2
	fi
)

candidate_interfaces() (
	ip -o link show \
	  | sed -e 's/^[0-9]*: \([^@:]*\)\(@[^:]*\)*:.*$/\1/; \
		    /^\(lo\|bond[0-9]*\|\)$/d'
	  | sort
)

is_dot1q_interface() (
	local tink_interface=$1

	return [[ "$tink_interface" =~ \.[0-9]+*$ ]]
)

validate_tinkerbell_network_interface() (
	local tink_interface=$1

	if is_dot1q_interface "$tink_interface" ; then
		if candidate_interfaces | grep -q "^$tink_interface$"; then
		    err "802.1q sub-interface $tink_interface already exists"
		    return 1
		else
		    return 0
		fi
	fi
		
	if ! candidate_interfaces | grep -q "^$tink_interface$"; then
		err "Invalid interface ($tink_interface) selected, must be one of:"
		candidate_interfaces | err
		return 1
	else
		return 0
	fi
)

generate_password() (
	head -c 12 /dev/urandom | sha256sum | cut -d' ' -f1
)

generate_env() (
	local tink_interface=$1

	validate_tinkerbell_network_interface "$tink_interface"
	local nginx_port
	if is_dot1q_interface "$tink_interface" ; then
	  nginx_port=8080
	else
	  nginx_port=80
	fi

	local tink_password
	tink_password=$(generate_password)
	local registry_password
	registry_password=$(generate_password)

	cat <<-EOF
		# Tinkerbell Stack version
		export COMPOSE_PROJECT_NAME=tinkerbell
		export STATEDIR=./state

		export OSIE_DOWNLOAD_LINK=${OSIE_DOWNLOAD_LINK}
		export TINKERBELL_TINK_SERVER_IMAGE=${TINKERBELL_TINK_SERVER_IMAGE}
		export TINKERBELL_TINK_CLI_IMAGE=${TINKERBELL_TINK_CLI_IMAGE}
		export TINKERBELL_TINK_BOOTS_IMAGE=${TINKERBELL_TINK_BOOTS_IMAGE}
		export TINKERBELL_TINK_HEGEL_IMAGE=${TINKERBELL_TINK_HEGEL_IMAGE}
		export TINKERBELL_TINK_WORKER_IMAGE=${TINKERBELL_TINK_WORKER_IMAGE}

		# Network interface for Tinkerbell's network
		export TINKERBELL_NETWORK_INTERFACE="$tink_interface"

		# Decide on a subnet for provisioning. Tinkerbell should "own" this
		# network space. Its subnet should be just large enough to be able
		# to provision your hardware.
		export TINKERBELL_CIDR=29

		# Host IP is used by provisioner to expose different services such as
		# tink, boots, etc.
		#
		# The host IP should the first IP in the range, and the Nginx IP
		# should be the second address.
		export TINKERBELL_HOST_IP=192.168.1.1

		# Tink server username and password
		export TINKERBELL_TINK_USERNAME=admin
		export TINKERBELL_TINK_PASSWORD="$tink_password"

		# Docker Registry's username and password
		export TINKERBELL_REGISTRY_USERNAME=admin
		export TINKERBELL_REGISTRY_PASSWORD="$registry_password"
		export TINKERBELL_NGINX_PORT="$nginx_port"

		# Legacy options, to be deleted:
		export FACILITY=onprem
		export ROLLBAR_TOKEN=ignored
		export ROLLBAR_DISABLE=1
	EOF
)

main() (
	if [[ -z ${1:-} ]]; then
		err "Usage: $0 network-interface-name > .tink-env"
		exit 1
	fi

	generate_env "$1"
)

main "$@"
