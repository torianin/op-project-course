FROM ruby:3.3-slim-bookworm AS base

ENV RACK_ENV=production \
    PORT=8080 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_FROZEN=true \
    BUNDLE_WITHOUT=development:test

WORKDIR /app

FROM base AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ make libssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 2.5.22 --no-document \
    && bundle install --jobs 4 --retry 3

FROM base AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libssl3 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system app \
    && useradd --system --gid app --home-dir /app app

COPY --from=build /usr/local/bundle/ /usr/local/bundle/
COPY --chown=app:app Gemfile Gemfile.lock server.rb config.ru ./
COPY --chown=app:app lib/ ./lib/
COPY --chown=app:app views/ ./views/
COPY --chown=app:app public/ ./public/

USER app

EXPOSE 8080
CMD ["bundle", "exec", "ruby", "server.rb"]
