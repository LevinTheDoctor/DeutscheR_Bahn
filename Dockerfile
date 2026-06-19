FROM rocker/r-ver:4.6.0

# Buildx füllt TARGETARCH automatisch (amd64 oder arm64).
ARG TARGETARCH

# System-Libs für die R-Pakete:
#   xml2          -> libxml2-dev
#   httr2/curl    -> libcurl4-openssl-dev, libssl-dev, curl (CLI)
#   fs            -> libuv1-dev (PPM-Binary linkt dynamisch dagegen)
#   git2r/gert    -> libgit2-dev (häufig von renv genutzt)
#   ggplot2-Plots -> libfontconfig, libfreetype, libpng, libtiff, libjpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
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

# Auf amd64 nutzen wir den Posit Package Manager (Linux-Binaries → schnell).
# Auf arm64 (z.B. Raspberry Pi) gibt's bei PPM keine Binaries, also Cloud-CRAN
# (Source-Build, langsamer aber zuverlässig).
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))' > /usr/local/lib/R/etc/Rprofile.site; \
    else \
      echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' > /usr/local/lib/R/etc/Rprofile.site; \
    fi

# renv installieren, danach Lockfile-Dateien einzeln kopieren,
# damit Docker den Restore-Step cached, solange sich renv.lock nicht ändert.
RUN R -e "install.packages('renv')"

COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/ renv/

# Pakete aus dem Lockfile installieren.
RUN R -e "renv::restore(prompt = FALSE)"

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
