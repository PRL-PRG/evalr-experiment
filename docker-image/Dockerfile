FROM prlprg/r-dyntrace:r-4.0.2

# install additional packages
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update -yqq && \
    apt-get install -yqq \
      gdb \
      locales \
      libharfbuzz-dev \
      libfribidi-dev \
      openssh-server \
      python3-pip \
      rr

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV LANG en_US.UTF-8

# TODO not sure why do I need to create the directory manually
RUN mkdir -p /run/sshd && \
  sed -ri 's/^#?MaxStartups\s+.*/MaxStartups 100:30:1000/' /etc/ssh/sshd_config && \
  sed -ri 's/^#?MaxSessions\s+.*/MaxSessions 500/' /etc/ssh/sshd_config && \
  sed -ri 's/^#?X11Forwarding\s+.*/X11Forwarding no/' /etc/ssh/sshd_config

RUN sed -ri 's/^#?\s*StrictHostKeyChecking\s+.*/StrictHostKeyChecking no/' /etc/ssh/ssh_config

# latest GNU parallel
RUN mkdir parallel && \
    cd parallel && \
    curl http://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2 | tar -xjf- --strip 1 && \
    ./configure && \
    make install && \
    mkdir /root/.parallel && \
    touch /root/.parallel/will-cite

# install fd
RUN wget -O /tmp/fd.deb https://github.com/sharkdp/fd/releases/download/v8.2.1/fd_8.2.1_amd64.deb && \
  dpkg -i /tmp/fd.deb && \
  rm -f /tmp/fd.deb

ENV R_PROJECT_BASE_DIR="/R" \
    TERM=xterm

RUN useradd -u 1000 -m -U -G sudo -s /bin/bash r && \
  echo "%sudo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
  echo "Defaults secure_path=\"$PATH\"" >> /etc/sudoers && \
  touch /home/r/.sudo_as_admin_successful && \
  mkdir /home/r/.parallel && \
  touch /home/r/.parallel/will-cite && \
  mkdir -m 700 /home/r/.ssh

ADD id_rsa id_rsa.pub /home/r/.ssh/

RUN cp /home/r/.ssh/id_rsa.pub /home/r/.ssh/authorized_keys && \
  chown -R r:r /home/r/.ssh && \
  chmod 600 /home/r/.ssh/id_rsa && \
  chmod 644 /home/r/.ssh/id_rsa.pub && \
  chmod 600 /home/r/.ssh/authorized_keys

ADD entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
