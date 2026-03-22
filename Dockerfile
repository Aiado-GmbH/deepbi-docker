FROM python:3.8.18-slim

EXPOSE 8338 8339 8340

ARG skip_dev_deps=yes

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl gnupg build-essential pwgen libffi-dev sudo git-core \
      libpq-dev g++ unixodbc-dev xmlsec1 libssl-dev \
      default-libmysqlclient-dev freetds-dev libsasl2-dev unzip \
      libsasl2-modules-gssapi-mit && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Node.js 16 and yarn
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/DeepInsight-AI/DeepBI.git /app

WORKDIR /app

# Install JS deps
RUN npm install --legacy-peer-deps

# Add babel deps to handle ESM class fields and modern syntax (webpack 4 / acorn 6 can't parse them)
RUN npm install --no-save --legacy-peer-deps \
      @babel/core @babel/preset-env babel-loader \
      @babel/plugin-proposal-class-properties \
      @babel/plugin-proposal-nullish-coalescing-operator \
      @babel/plugin-proposal-optional-chaining

# Wrapper webpack config: add babel-loader for fast-png + iobuffer (both use ESM class fields / ??)
RUN node -e " \
const fs = require('fs'); \
const patch = \`\
// Wrapper: transpile ESM packages incompatible with webpack 4 acorn parser\n\
delete require.cache[require.resolve('./webpack.config.js')];\n\
const config = require('./webpack.config.js');\n\
if (!config.module) config.module = {};\n\
if (!config.module.rules) config.module.rules = [];\n\
config.module.rules.push({\n\
  test: /\\\\.js\$/,\n\
  include: /node_modules\\\\/(fast-png|iobuffer)/,\n\
  use: {\n\
    loader: 'babel-loader',\n\
    options: {\n\
      presets: [['@babel/preset-env', { targets: { node: '10' }, loose: true }]],\n\
      plugins: [\n\
        ['@babel/plugin-proposal-class-properties', { loose: true }],\n\
        '@babel/plugin-proposal-nullish-coalescing-operator',\n\
        '@babel/plugin-proposal-optional-chaining',\n\
      ],\n\
    },\n\
  },\n\
});\n\
module.exports = config;\n\
\`; \
fs.writeFileSync('/app/webpack.config.patched.js', patch); \
console.log('Written webpack.config.patched.js'); \
"

# Build frontend using patched config
RUN NODE_ENV=production node --max-old-space-size=4096 node_modules/.bin/webpack --config webpack.config.patched.js

ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1

RUN pip install pip==20.2.4 && \
    pip install -r vrequment.txt

RUN sed -i 's/from importlib_resources import path/from importlib.resources import path/g' \
      /usr/local/lib/python3.8/site-packages/saml2/sigver.py && \
    sed -i 's/from importlib_resources import path/from importlib.resources import path/g' \
      /usr/local/lib/python3.8/site-packages/saml2/xml/schema/__init__.py

RUN chmod +x /app/bin/docker-entrypoint

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["server"]
