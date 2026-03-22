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

# Build frontend
RUN npm install --legacy-peer-deps && \
    NODE_ENV=production node --max-old-space-size=4096 node_modules/.bin/webpack

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
