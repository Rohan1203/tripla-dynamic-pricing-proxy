# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.2.6
FROM ruby:$RUBY_VERSION-alpine

# Rails app lives here
WORKDIR /rails

# Set development environment
ENV RAILS_ENV="production" \
    RATE_API="http://rate-api:8080/pricing" \
    REDIS_HOST="redis" \
    REDIS_PASSWORD="04aa6f42aa03f220c2ae9a276cd68c62" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT=""

RUN apk add --no-cache \
    build-base \
    git \
    pkgconfig \
    curl \
    sqlite-dev \
    sqlite \
    tzdata


COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["sh", "-c", "bin/rails db:prepare && bin/rails server -b 0.0.0.0"]
