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

# Add babel deps to handle fast-png ESM class fields (webpack 4 can't parse them)
RUN npm install --no-save @babel/core @babel/preset-env @babel/plugin-proposal-class-properties babel-loader

# Wrapper webpack config that patches the original to add a babel-loader rule for fast-png
RUN node -e " \
const fs = require('fs'); \
const patch = \`\
// Wrapper: add babel-loader for fast-png ESM (class fields incompatible with webpack 4)\n\
delete require.cache[require.resolve('./webpack.config.js')];\n\
const config = require('./webpack.config.js');\n\
if (!config.module) config.module = {};\n\
if (!config.module.rules) config.module.rules = [];\n\
config.module.rules.push({\n\
  test: /\\\\.js\$/,\n\
  include: /node_modules\\\\/fast-png/,\n\
  use: {\n\
    loader: 'babel-loader',\n\
    options: {\n\
      presets: [['@babel/preset-env', { targets: { node: '16' } }]],\n\
      plugins: ['@babel/plugin-proposal-class-properties'],\n\
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
