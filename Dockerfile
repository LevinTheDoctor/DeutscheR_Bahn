FROM rocker/r-ver:4.6.0

# System-Libs für die R-Pakete:
#   xml2          -> libxml2-dev
#   httr2/curl    -> libcurl4-openssl-dev, libssl-dev, curl (CLI)
#   fs            -> libuv1-dev (PPM-Binary linkt dynamisch dagegen), cmake
#   git2r/gert    -> libgit2-dev (häufig von renv genutzt)
#   knitr/rmarkdown -> pandoc
#   ggplot2-Plots -> libfontconfig, libfreetype, libpng, libtiff, libjpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      cmake \
      pandoc \
      libxml2-dev \
      libcurl4-openssl-dev \
      libssl-dev \
      libuv1-dev \
      libgit2-dev \
      libfontconfig1-dev \
      libfreetype6-dev \
      libpng-dev \
      libtiff5-dev \
      libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Wir nutzen CRAN-Cloud als Repo (statt PPM-latest), weil:
# - PPM-`latest` ist ein rolling Tag ohne Archive. Wenn die Lockfile xfun 0.58
#   pinnt, PPM aber inzwischen nur noch 0.59 anbietet, scheitert renv::restore.
# - CRAN-Cloud hat alle archivierten Versionen → reproduzierbare Builds.
# Trade-off: Source-Builds sind langsamer, aber zuverlässig auf amd64 + arm64.
ENV RENV_CONFIG_REPOS_OVERRIDE=https://cloud.r-project.org
RUN echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' > /usr/local/lib/R/etc/Rprofile.site

# renv installieren, danach Lockfile-Dateien einzeln kopieren,
# damit Docker den Restore-Step cached, solange sich renv.lock nicht ändert.
RUN R -e "install.packages('renv')"

COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/ renv/

# Pakete aus dem Lockfile installieren.
# Retry-Loop: PPM-Downloads brechen gelegentlich ab (Truncated TAR / EOF).
# Bis zu 3 Versuche, danach gibt der letzte Exit-Code auf.
RUN for i in 1 2 3; do \
      echo "renv::restore() attempt $i/3"; \
      R -e "options(timeout = 600); renv::restore(prompt = FALSE)" && exit 0; \
      echo "Attempt $i failed, sleeping 15s..."; \
      sleep 15; \
    done; \
    exit 1

# Erst jetzt den App-Code kopieren — Code-Änderungen invalidieren
# nicht den Paket-Cache.
COPY app.R app.R
COPY R/ R/

# Shiny-Port
EXPOSE 3838

# Healthcheck (optional, aber nett für Compose/Kubernetes)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl --fail http://localhost:3838/ || exit 1

# App starten und auf allen Interfaces lauschen, damit Docker reinkommt
CMD ["R", "-e", "shiny::runApp('/app', host = '0.0.0.0', port = 3838)"]
