#!/bin/bash

# Variables to set
IMAGE_BASE=komacke/open-hamclock-backend
VOACAP_VERSION=v.0.7.6
HTTP_PORT=80

# Don't set anything past here
TAG=$(git describe --exact-match --tags 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Not currently on a tag. Using 'latest'."
    TAG=latest
    # should we use the git hash?
    #TAG=$(git rev-parse --short HEAD)
fi

IMAGE=$IMAGE_BASE:$TAG
CONTAINER=${IMAGE_BASE##*/}

# Get our directory locations in figured out
HERE="$(realpath -s "$(dirname "$0")")"
THIS="$(basename "$0")"
cd $HERE

RETVAL=0

main() {
    case $1 in
        compose)
            make_docker_compose
            ;;
        '')
            do_all 
            ;;
    esac
}

do_all() {
    get_voacap
    make_docker_compose
    warn_image_tag
    build_image
    done_message
}

get_voacap() {
    # this hasn't changed since 2020. Also, while we are developing we don't need to keep pulling it.
    if [ ! -e voacap-$VOACAP_VERSION.tgz ]; then
        curl -s https://codeload.github.com/jawatson/voacapl/tar.gz/refs/tags/v.0.7.6 -o voacap-$VOACAP_VERSION.tgz
    fi
}

make_docker_compose() {
    # make the docker-compose file
    sed "s|__IMAGE__|$IMAGE|" docker-compose.yml.tmpl > docker-compose.yml
    sed -i "s/__CONTAINER__/$CONTAINER/" docker-compose.yml
    sed -i "s/__HTTP_PORT__/$HTTP_PORT/" docker-compose.yml
}

warn_image_tag() {
    if $(docker image list --format '{{.Repository}}:{{.Tag}}' | grep -qs $IMAGE) && [ $TAG != latest ]; then
        echo "The docker image for '$IMAGE' already exists. Please remove it if you want to rebuild."
        # NOT ENFORCING THIS YET
        #exit 2
    fi
}

build_image() {
    # Build the image
    echo
    echo "Currently building version '$TAG' of '$IMAGE_BASE'"
    pushd "$HERE/.." >/dev/null
    docker build --rm -t $IMAGE -f docker/Dockerfile .
    RETVAL=$?
    popd >/dev/null
}

done_message() {
	if [ $RETVAL -eq 0 ]; then
		# basic info
		echo
		echo "Completed building '$IMAGE'."
		echo
		echo "If this is the first time you are running OHB, run setup first:"
		echo "    docker-ohb-setup.sh"
		echo
		echo "To start the container, launch with docker compose:"
		echo "    docker compose up -d"
	else
		echo "build failed with error: $RETVAL"
	fi
}

main "$@"
exit $RETVAL
