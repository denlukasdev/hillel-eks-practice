# ---------------------------------------------------------------------------
# Заняття 12. Образ застосунку shop.
#
# Досі web і api працювали на готовому образі nginx із Docker Hub, а вся
# різниця між ними була в ConfigMap. Щоб було що збирати й версіонувати,
# робимо власний образ: той самий nginx плюс файл із відомостями про збірку.
#
# VERSION і COMMIT передає CI:  docker build --build-arg VERSION=0.2.15 ...
# Вони потрапляють у файл, який чарт віддає за адресою /version.
# Так у браузері видно, ЯКА САМЕ збірка зараз працює в кластері.
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine

ARG VERSION=dev
ARG COMMIT=unknown

RUN printf 'version: %s\ncommit: %s\n' "$VERSION" "$COMMIT" \
      > /usr/share/nginx/html/version.txt

# Мітки OCI: за ними в реєстрі видно, з якого коду зібрано образ.
LABEL org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.revision="$COMMIT" \
      org.opencontainers.image.title="shop"
