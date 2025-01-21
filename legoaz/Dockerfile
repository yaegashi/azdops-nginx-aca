FROM goacme/lego as lego
FROM mcr.microsoft.com/azure-cli:cbl-mariner2.0
COPY --from=lego /lego /usr/bin/lego
