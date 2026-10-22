# Serves the release signature of one OpenShift version over HTTP from the web root.
#
# The OCP_VERSION default below is the single source of truth for the version.
# .github/workflows/track-openshift-release.yaml bumps it when a new release is
# published on the tracked channel, commits, and pushes a git tag with the same
# version. A Quay.io build trigger on that tag builds and tags the image.
#
# Local build (override with any x.y.z, or a mirror channel such as stable,
# stable-4.22, fast-4.22 or latest):
#   podman build -t signature-server:4.22.17 -f Containerfile .
#   podman build --build-arg OCP_VERSION=stable -t signature-server:stable -f Containerfile .
#
# URL: http://<host>:8080/sha256%3D<digest>/signature-1
#
# nginx percent-decodes the request URI before mapping it to the filesystem,
# so the "%3D" in the URL must be a literal "=" in the on-disk directory name.
# Requests using either "%3D" or "=" resolve to the same file.

ARG OCP_VERSION=4.22.17

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest AS fetch

ARG OCP_VERSION
ARG ARCH=x86_64
ARG MIRROR=https://mirror.openshift.com/pub/openshift-v4

RUN set -eu; \
    test -n "${OCP_VERSION:-}" || { echo "OCP_VERSION must not be empty" >&2; exit 1; }; \
    curl -fsSL -o /tmp/release.txt "${MIRROR}/${ARCH}/clients/ocp/${OCP_VERSION}/release.txt"; \
    digest="$(awk '/^Digest:/ { print $2; exit }' /tmp/release.txt)"; \
    case "${digest}" in sha256:*) ;; *) echo "no digest found for ${OCP_VERSION}" >&2; exit 1 ;; esac; \
    dir="/signatures/sha256=${digest#sha256:}"; \
    mkdir -p "${dir}"; \
    curl -fsSL -o "${dir}/signature-1" "${MIRROR}/signatures/openshift/release/sha256=${digest#sha256:}/signature-1"; \
    echo "OpenShift ${OCP_VERSION} (${ARCH}): $(awk '/^Name:/ { print $2; exit }' /tmp/release.txt) ${digest}"

FROM registry.access.redhat.com/ubi9/nginx-124:latest

ARG OCP_VERSION
LABEL org.opencontainers.image.version="${OCP_VERSION}" \
      org.opencontainers.image.title="OpenShift ${OCP_VERSION} release signature"

COPY --from=fetch --chown=1001:0 /signatures/ /opt/app-root/src/

USER 1001
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
