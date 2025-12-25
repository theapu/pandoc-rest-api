#            _
#   _____  _| |_ _ __ __ _
#  / _ \ \/ / __| '__/ _` |
# |  __/>  <| |_| | | (_| |
#  \___/_/\_\\__|_|  \__,_|
#
FROM pandoc/latex:3.8.3-ubuntu

# uv is our preferred manager for Python packages
# but we keep pip for compatibility with downstream images
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_TOOL_BIN_DIR=/usr/local/bin/
ENV UV_TOOL_DIR=/usr/local/share/uv/tools

# ------------------------------------------------------------
# 1. System Dependencies & Pandoc Tools
# ------------------------------------------------------------
RUN apt-get -q --no-allow-insecure-repositories update && \
    apt-get install --assume-yes --no-install-recommends \
    python3-pip \
    python3-venv \
    procps && \
    uv tool install 'pandoc-codeblock-include==1.1.*' && \
    uv tool install 'pandoc-latex-environment==1.2.*' && \
    uv tool install 'pandoc-include==1.4.*'

# ------------------------------------------------------------
# 2. LaTeX Packages
# ------------------------------------------------------------
RUN tlmgr install \
        abstract \
        adjustbox \
        awesomebox \
        babel-german \
        background \
        beamertheme-metropolis \
        bidi \
        catchfile \
        cm-super \
        collectbox \
        csquotes \
        draftwatermark \
        enumitem \
        environ \
        etoolbox \
        everypage \
        filehook \
        fontawesome5 \
        footmisc \
        footnotebackref \
        framed \
        fvextra \
        hardwrap \
        incgraph \
        koma-script \
        letltxmacro \
        lineno \
        listingsutf8 \
        ly1 \
        mdframed \
        mweights \
        needspace \
        pagecolor \
        pgf \
        pgfopts \
        sectsty \
        sourcecodepro \
        sourcesanspro \
        sourceserifpro \
        tcolorbox \
        tikzfill \
        titlesec \
        titling \
        transparent \
        trimspaces \
        ucharcat \
        ulem \
        unicode-math \
        upquote \
        xecjk \
        xltxtra \
        xurl \
        zref

# ------------------------------------------------------------
# 3. Templates (Eisvogel)
# ------------------------------------------------------------
ENV PANDOC_DATA_HOME=/usr/local/share/pandoc
ENV PANDOC_TEMPLATES_DIR=${PANDOC_DATA_HOME}/templates
RUN mkdir -p ${PANDOC_TEMPLATES_DIR}

ARG EISVOGEL_REPO=https://github.com/Wandmalfarbe/pandoc-latex-template/releases/download
RUN wget -qO- ${EISVOGEL_REPO}/v3.2.0/Eisvogel.tar.gz \
    | tar xz \
        --strip-components=1 \
        --one-top-level=${PANDOC_TEMPLATES_DIR} \
        Eisvogel-3.2.0/eisvogel.latex \
        Eisvogel-3.2.0/eisvogel.beamer

# ------------------------------------------------------------
# 4. Lua Filters
# ------------------------------------------------------------
ARG LUA_FILTERS_REPO=https://github.com/pandoc/lua-filters/releases/download
ARG LUA_FILTERS_VERSION=2021-11-05
RUN wget -qO- ${LUA_FILTERS_REPO}/v${LUA_FILTERS_VERSION}/lua-filters.tar.gz \
    | tar xz \
        --strip-components=1 \
        --one-top-level=${PANDOC_DATA_HOME}

# ------------------------------------------------------------
# 5. Tectonic (PDF Engine)
# ------------------------------------------------------------
ARG TARGETARCH
ARG TECTONIC_REPO=https://github.com/tectonic-typesetting/tectonic/releases/download
ARG TECTONIC_VERSION=0.15.0
RUN <<EOF
set -ex;
case "$TARGETARCH" in
    (amd64)
        TECTONIC_ARCH='x86_64';
        TECTONIC_CLIB='gnu';
        ;;
    (arm64)
        TECTONIC_ARCH='aarch64' ;
        TECTONIC_CLIB='musl';
        ;;
    (*)
        printf 'unsupported target arch for tectonic: %s\n' "$TARGETARCH";
        exit 1 ;
        ;;
esac
TECTONIC_TARBALL_FMT='tectonic-%s-%s-unknown-linux-%s.tar.gz'
TECTONIC_TARBALL="$(printf "$TECTONIC_TARBALL_FMT" \
    "${TECTONIC_VERSION}" "${TECTONIC_ARCH}" "${TECTONIC_CLIB}" \
)"
wget ${TECTONIC_REPO}/tectonic%40${TECTONIC_VERSION}/${TECTONIC_TARBALL}
tar xzf ${TECTONIC_TARBALL} -C /usr/local/bin/
rm -f ${TECTONIC_TARBALL}
EOF

# ------------------------------------------------------------
# 6. REST API Setup (New Addition)
# ------------------------------------------------------------

# Create a virtual environment specifically for the API
# We use /opt/venv to keep it separate from system python to avoid PEP 668 errors
ENV VIRTUAL_ENV=/opt/venv
RUN uv venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Set default PDF engine for Unicode support (can be overridden by passing PDF_ENGINE env var)
# Options: pdflatex (default), xelatex (unicode), tectonic (modern/fast)
ENV PDF_ENGINE=xelatex

# Install dependencies into the virtual environment
RUN uv pip install flask gunicorn werkzeug

# Copy the API application code
WORKDIR /app
COPY app.py /app/app.py

# Expose the port
EXPOSE 5000

# IMPORTANT: Reset the entrypoint. 
# The base image (pandoc/latex) sets ENTRYPOINT ["/usr/local/bin/pandoc"].
# We must clear this so we can run python/gunicorn instead.
ENTRYPOINT []

# Run Gunicorn server
# Workers: 4 workers to handle concurrent requests
# Timeout: 120 seconds because PDF generation can be slow
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--timeout", "120", "app:app"]