FROM node:16.2.0

RUN npm i -g sirv-cli

WORKDIR /opt/app