# Containerfile for running showoff from local source
#
# Build:
#   podman build -t showoff-local -f Containerfile .
#
# Run (mount your presentation at /presentation):
#   podman run -it --rm -p 54321:54321 -v /path/to/your/presentation:/presentation:Z showoff-local
#
# Access the presentation at http://localhost:54321
# Access the presenter view at http://localhost:54321/presenter

FROM ruby:3.3-alpine

# Build dependencies for native gem extensions
# - build-base: gcc, make, etc.
# - cmake: required by commonmarker
# - git: some gems may need it
# - libxml2-dev, libxslt-dev: required by nokogiri at build time
# - zlib-dev: compression support
RUN apk add --no-cache --virtual .build-deps \
        build-base \
        cmake \
        git \
        libxml2-dev \
        libxslt-dev \
        zlib-dev

# Runtime dependencies
# - libxml2, libxslt: nokogiri runtime
# - zlib: compression
# - libstdc++: required by eventmachine native extension
RUN apk add --no-cache \
        libxml2 \
        libxslt \
        zlib \
        libstdc++

# Install showoff from local source
WORKDIR /showoff
COPY Gemfile Gemfile.lock* showoff.gemspec ./
COPY lib/showoff/version.rb lib/showoff/version.rb

# Install dependencies
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4

# Copy the rest of the application
COPY . .

# Clean up build dependencies to reduce image size
RUN apk del .build-deps

# Create mount point for presentations
# Users must mount their presentation directory here
RUN mkdir -p /presentation
VOLUME /presentation

WORKDIR /presentation

EXPOSE 54321

# Use the locally installed showoff
ENV PATH="/showoff/bin:${PATH}"

ENTRYPOINT ["showoff"]
CMD ["serve", "--host", "0.0.0.0", "--port", "54321", "--hot-reload"]
