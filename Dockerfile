FROM registry.access.redhat.com/ubi8/ubi:latest

RUN dnf install -y wget tar golang bc && dnf clean all

COPY run.sh /opt/peak/
COPY util /opt/peak/
COPY operator-tests/common /opt/peak/operator-tests/
COPY test/ /opt/peak/test 
RUN chgrp -R 0 /opt/peak && chmod -R g+rwX /opt/peak

RUN wget https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.2/linux/oc.tar.gz && \
    tar -xzf oc.tar.gz && mv oc /usr/local/bin

COPY image/bin /usr/local/bin
COPY image/s2i /usr/libexec/s2i
CMD ["/usr/libexec/s2i/usage"]

USER 1001 
