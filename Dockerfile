# Docker file lists all the commands needed to setup a fresh linux instance to run the application specified
# It is split into two stages, each with a separate container:
# 1. (NodeJS) builds the static assets (Vue, SCSS) and is disarded after the assets are copied
# 2. (Python) installs the runtime dependencies and runs the application

########################
#                      #
#   NodeJS container   #
#                      #
########################

# Barebones NodeJS image
FROM node:16-alpine AS node-build

WORKDIR /build

# Copy in dependency list and install the dependencies
# Note: This is copied separately from the rest of the code to take advantage of build caching
COPY ./package.json ./package-lock.json ./
RUN npm install --only=production

# Copy files, required for the build
# TODO: is there a way to copy only JS-related files to take advantage of build caching?
COPY . ./

# Build the static files
RUN npm run build


########################
#                      #
#   Django container   #
#                      #
########################

# Grab a python image
FROM python:3.9-slim

# Just needed for all things python (note this is setting an env variable)
ENV PYTHONUNBUFFERED 1
# Needed for correct settings input
ENV IN_DOCKER 1

# Copy all our files into the baseimage and cd to that directory
RUN mkdir /tcd
WORKDIR /tcd

# Install Nginx and clear APT cache afterwards
# NOTE: all of this is under one RUN directive so only one layer is created and the final image is smaller
RUN apt-get update && \
        apt-get install -y nginx && \
        apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Pipenv
RUN pip install pipenv==2023.12.1

# Copy in dependency list and install the dependencies
# NOTE: This is copied separately from the rest of the code to take advantage of build caching
RUN mkdir -p ./config/
COPY ./Pipfile* ./
RUN pipenv install --system --deploy

# Copy the built JS files
RUN mkdir -p ./tabbycat/static/vue
COPY --from=node-build /build/tabbycat/static/ /tcd/tabbycat/static/

# Copy the rest of the Python source code
ADD . /tcd/

# Bundle the static files into the image
RUN python ./tabbycat/manage.py collectstatic --noinput -v 0
