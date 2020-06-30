# ---- Build Stage ----
FROM elixir:1.10.3-alpine AS app_builder

# Set environment variables for building the application
ENV MIX_ENV=prod
ENV LANG=C.UTF-8

# install build dependencies
RUN apk add --update git build-base nodejs npm yarn python

# Install hex and rebar
RUN mix local.hex --force \
 && mix local.rebar --force

# Create the application build directory
WORKDIR /app

# install mix dependencies
COPY mix.* ./
COPY config config
RUN mix deps.get \
 && mix release.init \
 && mix deps.compile --force --only $MIX_ENV 

# build assets
COPY assets assets
COPY priv priv
RUN cd assets \
 && npm install \
 && npm run deploy
RUN mix phx.digest

# build project and release
COPY lib lib
RUN mix compile \ 
 && mix release

# ---- Application Stage ----
FROM alpine as app

ENV MIX_ENV=prod
ENV LANG=C.UTF-8

# Install openssl
RUN apk --no-cache --update upgrade \ 
 && apk add --no-cache --update openssl \
                                inotify-tools \
                                linux-headers \
                                bash \
                                docker \
                                git


# create a non root user
RUN addgroup -S appgroup && adduser -S app_user -G appgroup

WORKDIR /home/app_user

# Configure Git
# Create the .ssh directory under /home/app_user/.ssh and copy in keys.
# Must ensure they have the correct file permissions or Git will complain
RUN mkdir $HOME/.ssh
RUN chown -R $USER:appgroup $HOME/.ssh
RUN chmod -R 750 $HOME/.ssh
COPY tmp/.ssh/id_rsa tmp/.ssh/id_rsa.pub $HOME/.ssh/
RUN chmod -R 600 $HOME/.ssh/id_rsa
RUN chmod -R 600 $HOME/.ssh/id_rsa.pub

# Create the .docker directory under /home/app_user/.docker and copy in the config to enable builx
RUN mkdir -p $HOME/.docker/cli-plugins
COPY buildx/config.json $HOME/.docker/
# Have to copy in buildx for now since it isn't installed by default in the docker images
# Also have to use 0.4.0 because 0.4.1 has a bug with parsing JSON which is fixed on master, but
# no 0.4.2 release yet
COPY buildx/buildx-v0.4.0.linux-amd64 $HOME/.docker/cli-plugins/docker-buildx
RUN chown -R $USER:appgroup $HOME/.docker
RUN chmod -R 755 $HOME/.docker

# Create the .kube directory under /home/app_user/.kube and copy in the local config
RUN mkdir -p $HOME/.kube/
ADD tmp/.kube/config $HOME/.kube/config

# Build Args mapped to Envs to allow customization of the Buildx servers
ARG BUILDX_NAME
ARG BUILDER_REPLICAS
ARG BUILDER_NAMESPACE
ENV BUILDX_NAME=$BUILDX_NAME
ENV BUILDER_REPLICAS=$BUILDER_REPLICAS
ENV BUILDER_NAMESPACE=$BUILDER_NAMESPACE

# Copy over the build artifact from the previous step 
COPY --from=app_builder /app/_build/${MIX_ENV}/rel .

COPY entrypoint.sh .

RUN chmod 755 entrypoint.sh

RUN chown -R app_user: .

USER app_user

CMD ["sh", "entrypoint.sh"]