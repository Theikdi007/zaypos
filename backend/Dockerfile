# ZayPOS API image. Build from backend/:
#   docker buildx build --platform linux/amd64 -t zaypos-api:<tag> .
# The SDK stage runs on the build machine's own architecture and cross-publishes for the
# target (fast on Apple Silicon; no emulation). The runtime stage runs as a non-root user.

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
WORKDIR /src

# Restore first (cached until a project file changes).
COPY src/ZayPOS.Domain/ZayPOS.Domain.csproj src/ZayPOS.Domain/
COPY src/ZayPOS.Application/ZayPOS.Application.csproj src/ZayPOS.Application/
COPY src/ZayPOS.Infrastructure/ZayPOS.Infrastructure.csproj src/ZayPOS.Infrastructure/
COPY src/ZayPOS.Api/ZayPOS.Api.csproj src/ZayPOS.Api/
RUN dotnet restore src/ZayPOS.Api/ZayPOS.Api.csproj -a $TARGETARCH

COPY src/ src/
RUN dotnet publish src/ZayPOS.Api/ZayPOS.Api.csproj -c Release -a $TARGETARCH --no-restore \
        -o /app /p:UseAppHost=false \
    # Never ship local dev settings, even if .dockerignore is bypassed.
    && rm -f /app/appsettings.Development*.json

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
# curl: only for the container health check (GET /health on loopback).
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build --chown=root:root /app .

ENV ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_ENVIRONMENT=Production \
    ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1
EXPOSE 8080

# "app" (uid 1654) ships with the .NET images; it cannot write to /app.
USER $APP_UID

# "localhost", not 127.0.0.1: AllowedHosts (host filtering) only lets the real domain and localhost in.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --start-interval=3s --retries=3 \
    CMD curl -fsS http://localhost:8080/health > /dev/null || exit 1

ENTRYPOINT ["dotnet", "ZayPOS.Api.dll"]
