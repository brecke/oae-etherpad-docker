#
# Copyright 2017 Apereo Foundation (AF) Licensed under the
# Educational Community License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may
# obtain a copy of the License at
#
#     http://opensource.org/licenses/ECL-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an "AS IS"
# BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing
# permissions and limitations under the License.
#

#
# Setup in two steps
#
# Step 1: Build the image
# $ docker build -f Dockerfile -t oae-etherpad:latest .
# Step 2: Run the docker
# $ docker run -it --name=etherpad --net=host oae-etherpad:latest
#

# FROM alpine:3.6
FROM node:6.12.0-alpine
LABEL Name=AlpineDockerEtherpad
LABEL Author=ApereoFoundation 
LABEL Email=oae@apereo.org

#
# Install etherpad
#
ENV ETHERPAD_VERSION 1.6.2
ENV ETHERPAD_PATH /opt/etherpad

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && apk --no-cache add curl git su-exec \
    && addgroup -S -g 1001 etherpad \
    && adduser -S -u 1001 -G etherpad -G node etherpad \
    && curl -sLo /etherpad.tar.gz https://github.com/ether/etherpad-lite/archive/${ETHERPAD_VERSION}.tar.gz \
    && mkdir -p /opt \
    && tar -xz -C /opt -f /etherpad.tar.gz \
    && mv /opt/etherpad-lite-${ETHERPAD_VERSION} ${ETHERPAD_PATH} \
    && rm -f /etherpad.tar.gz \
    && sed -i -e "93 s,grep.*,grep -E -o 'v[0-9]\.[0-9](\.[0-9])?')," ${ETHERPAD_PATH}/bin/installDeps.sh \
    && sed -i -e '96 s,if.*,if [ "${VERSION#v}" = "$NEEDED_VERSION" ]; then,' ${ETHERPAD_PATH}/bin/installDeps.sh \
    && ${ETHERPAD_PATH}/bin/installDeps.sh \
    && rm -rf /tmp/*
# COPY settings.json /opt/etherpad/settings.json
RUN mv ${ETHERPAD_PATH}/settings.json.template ${ETHERPAD_PATH}/settings.json
COPY init.cql ${ETHERPAD_PATH}/init.cql
RUN chown -R etherpad:etherpad ${ETHERPAD_PATH}

# Next two lines are production config ONLY
RUN sed -i -e 's/defaultPadText" : ".*"/defaultPadText" : ""/g' ${ETHERPAD_PATH}/settings.json
RUN sed -i -e 's/dbType\" : \"dirty/dbType\" : \"cassandra/g' ${ETHERPAD_PATH}/settings.json
RUN sed -i -e 's/"filename" : "var\/dirty.db"/"clientOptions": {"keyspace": "etherpad", "port": 9160, "contactPoints": ["oae-cassandra"]},"columnFamily": "Etherpad"/g' ${ETHERPAD_PATH}/settings.json

# Install ep_headings module
RUN cd ${ETHERPAD_PATH} && npm install ep_headings

# Etherpad OAE plugin
RUN cd ${ETHERPAD_PATH}/node_modules \
  && git clone https://github.com/oaeproject/ep_oae \
  && cd ep_oae \
  && npm install

# Not strictly necessary if we're using default IP and port
RUN sed -i -e '/defaultPadText/a \
  "ep_oae": {"mq": { "host": "oae-rabbitmq", "port": 5672 } },' ${ETHERPAD_PATH}/settings.json

# CSS changes
RUN rm ${ETHERPAD_PATH}/node_modules/ep_headings/templates/editbarButtons.ejs && cp ${ETHERPAD_PATH}/node_modules/ep_oae/static/templates/editbarButtons.ejs ${ETHERPAD_PATH}/node_modules/ep_headings/templates/editbarButtons.ejs
RUN rm ${ETHERPAD_PATH}/src/static/custom/pad.css && cp ${ETHERPAD_PATH}/node_modules/ep_oae/static/css/pad.css ${ETHERPAD_PATH}/src/static/custom/pad.css

# Edit protocols in config
RUN sed -i -e 's/\["xhr-polling", "jsonp-polling", "htmlfile"\],/\["websocket", "xhr-polling", "jsonp-polling", "htmlfile"\],/g' ${ETHERPAD_PATH}/settings.json

# Edit toolbar in config
RUN sed -i -e '/"loadTest/a \
  "toolbar": {"left": [["bold", "italic", "underline", "strikethrough", "orderedlist", "unorderedlist", "indent", "outdent"]],"right": [["showusers"]]},' ${ETHERPAD_PATH}/settings.json


# We need to run a specific cqlsh command before this works
RUN apk --no-cache add python py-pip git bash
RUN pip install cqlsh==4.0.1
RUN pip install thrift==0.9.3
RUN echo "CREATE KEYSPACE IF NOT EXISTS etherpad WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" > ${ETHERPAD_PATH}/init.cql

# miguel addon
# USER etherpad

# debug and experimental
RUN echo "13SirapH8t3kxUh5T5aqWXhXahMzoZRA" > ${ETHERPAD_PATH}/APIKEY.txt

EXPOSE 9001
# ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/opt/etherpad/bin/run.sh"]
# CMD cqlsh -f ${ETHERPAD_PATH}/init.cql oae-cassandra 9160 && ${ETHERPAD_PATH}/bin/run.sh 
# CMD ["cqlsh",  "-f", "/opt/etherpad/init.cql", "oae-cassandra", "9160", "&&", "${ETHERPAD_PATH}/bin/run.sh"]