FROM ubuntu:jammy
COPY overlay-system-docker-run.sh /root
RUN  mkdir -p /mount-magic/root-org /mount-magic/root-merged \
              /mount-magic/overlay  /mount-magic/overlay-merged
ENTRYPOINT ["/root/overlay-system-docker-run.sh"]
