# Utilisation de Debian 12.9 (Bookworm) comme base
FROM debian:12.9-slim
# an image with OpenMPI4.1, used without root privileges for sshd
# XMP and telegraf
# ------------------------------------------------------------
# Do basic install
# ------------------------------------------------------------
RUN apt-get update \
    && mkdir -p /usr/share/man/man1 \
    && apt-get install -y gcc ssh wget vim curl net-tools bison flex autoconf make libtool m4 automake bzip2 libxml2 libxml2-dev gfortran g++ iputils-ping pkg-config colordiff nano git sudo lsof gawk emacs jq neofetch libtdl* astyle cmake gdb strace binutils-dev dnsutils netcat-traditional libgomp1 googletest supervisor \
    && apt-get install -y build-essential ninja-build python3 python3-pip libz-dev libtinfo-dev libedit-dev libxml2-dev clang \
    && adduser --uid 1000 --home /home/mpiuser --shell /bin/bash \
       --disabled-password --gecos '' mpiuser \
    && passwd -d mpiuser \
    && apt-get install -y openssh-server \
    && mkdir -p /run/sshd /home/mpiuser/.ssh /home/mpiuser/.ssh-source \
    && echo "StrictHostKeyChecking no" > /home/mpiuser/.ssh/config \
    && chown -R mpiuser /home/mpiuser \
    && sed -i s/#PermitRootLogin.*/PermitRootLogin\ no/ /etc/ssh/sshd_config \
    && sed -i s/#PubkeyAuthentication.*/PubkeyAuthentication\ no/ /etc/ssh/sshd_config \
    && sed -i s/.*UsePAM.*/UsePAM\ no/ /etc/ssh/sshd_config \
    && sed -i s/#PasswordAuthentication.*/PasswordAuthentication\ yes/ /etc/ssh/sshd_config \
    && sed -i s/#PermitEmptyPasswords.*/PermitEmptyPasswords\ yes/ /etc/ssh/sshd_config \
    && sed -i s/#ChallengeResponse.*/ChallengeResponseAuthentication\ no/ /etc/ssh/sshd_config \
    && sed -i s/#PermitUserEnvironment.*/PermitUserEnvironment\ yes/ /etc/ssh/sshd_config \
    && adduser mpiuser sudo

ENV PREFIX=/usr/local \
    OPENMPI_VERSION=4.1.8 \
    LD_LIBRARY_PATH=/usr/local/lib \
    DEBCONF_NOWARNINGS=yes

# Vulkan (SDK and library)
RUN apt-get update && apt-get install -y \
    vulkan-tools \
    libvulkan-dev \
    && rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------
# Install OpenMPI 4.1
# https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.8.tar.gz
# ------------------------------------------------------------

# OpenMPI v4.1
RUN repo="https://download.open-mpi.org/release/open-mpi/v4.1" \
    && curl --location --silent --show-error --output openmpi.tar.gz \
      "${repo}/openmpi-${OPENMPI_VERSION}.tar.gz" \
    && tar xzf openmpi.tar.gz -C /tmp/ \
    && cd /tmp/openmpi-${OPENMPI_VERSION} \
	&& env CFLAGS="-O2 -std=gnu99 -fopenmp" \
    && ./configure --prefix=${PREFIX} \
    && make \
    && make install \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/openmpi-${OPENMPI_VERSION} /home/mpiuser/openmpi.tar.gz

# ------------------------------------------------------------
# Add some parameters for MPI, mpishare - a folder shared through the nodes
# ------------------------------------------------------------	
RUN mkdir -p /usr/local/var/mpishare

RUN chown -R 1000:1000 /usr/local/var/mpishare

RUN echo "mpiuser ALL=(ALL) NOPASSWD:ALL\n" >> /etc/sudoers

RUN rm -fr /home/mpiuser/.openmpi && mkdir -p /home/mpiuser/.openmpi
RUN cd /home/mpiuser/.openmpi \
	&& echo "btl = tcp,self \n" \
	"btl_tcp_if_include = eth0 \n" \
	"plm_rsh_no_tree_spawn = 1 \n" >> default-mca-params.conf

RUN chown -R 1000:1000 /home/mpiuser/.openmpi

RUN echo "rmaps_base_oversubscribe = 1\n" >> /usr/local/etc/openmpi-mca-params.conf
RUN echo "rmaps_base_inherit = 1\n" >> /usr/local/etc/openmpi-mca-params.conf


# ------------------------------------------------------------
# The .ssh-source dir contains RSA keys - put in place with docker-compose
# ------------------------------------------------------------


RUN touch /home/mpiuser/.ssh-source/authorized_keys
RUN touch /home/mpiuser/.ssh-source/id_rsa


# ------------------------------------------------------------
# Do SSHd parameter to enable mpiuser to run it
# ------------------------------------------------------------
RUN sed -i s/#UsePrivilegeSeparation.*/UsePrivilegeSeparation\ no/ /etc/ssh/sshd_config
RUN mkdir -p /home/mpiuser/ssh
RUN ssh-keygen -q -N "" -t dsa -f /home/mpiuser/ssh/ssh_host_dsa_key \
	&& ssh-keygen -q -N "" -t rsa -b 4096 -f /home/mpiuser/ssh/ssh_host_rsa_key \
	&& ssh-keygen -q -N "" -t ecdsa -f /home/mpiuser/ssh/ssh_host_ecdsa_key \
	&& ssh-keygen -q -N "" -t ed25519 -f /home/mpiuser/ssh/ssh_host_ed25519_key

RUN cp /etc/ssh/sshd_config /home/mpiuser/ssh/

RUN sed -i s/#HostKey\ \\/etc\\/ssh/HostKey\ \\/home\\/mpiuser\\/ssh/ /home/mpiuser/ssh/sshd_config
RUN sed -i s/#PidFile\ \\/var\\/run/PidFile\ \\/home\\/mpiuser\\/ssh/ /home/mpiuser/ssh/sshd_config
RUN sed -i s/#LogLevel.*/LogLevel\ DEBUG3/ /home/mpiuser/ssh/sshd_config
RUN sed -i s/PubkeyAuthentication\ no/PubkeyAuthentication\ yes/ /home/mpiuser/ssh/sshd_config

RUN chown -R mpiuser:mpiuser /home/mpiuser/ssh


# ------------------------------------------------------------
# Start mpi python install / user mpiuser
# ------------------------------------------------------------
# Update pip with --break-system-packages
RUN pip3 install --upgrade pip --break-system-packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-dev python3-numpy python3-pip python3-virtualenv python3-scipy 2to3 \
    && apt-get clean && apt-get purge && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# in order to have python related to mpiuser account
USER mpiuser
RUN  pip3 install --break-system-packages --user -U setuptools \
    && pip3 install --break-system-packages --user mpi4py
USER root

# ------------------------------------------------------------
# Load omni-compiler 1.3.4 from a public repo
# ------------------------------------------------------------
RUN mkdir -p /home/mpiuser/YMLEnvironment
WORKDIR /home/mpiuser/YMLEnvironment
RUN wget --no-check-certificate --content-disposition https://omni-compiler.org/download/stable/omnicompiler-1.3.4.tar.bz2
RUN bunzip2 omnicompiler-1.3.4.tar.bz2 \
	&& tar xvf omnicompiler-1.3.4.tar \
	&& rm /home/mpiuser/YMLEnvironment/omnicompiler-1.3.4.tar
	
# ------------------------------------------------------------
# Install omnicompiler-1.3.4 : requested javac
# ------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y openjdk-17-jdk-headless

WORKDIR /home/mpiuser/YMLEnvironment/omnicompiler-1.3.4
RUN cd /home/mpiuser/YMLEnvironment/omnicompiler-1.3.4 \
	&& export FCFLAGS="-w -fallow-argument-mismatch -O2" \
	&& export FFLAGS="-w -fallow-argument-mismatch -O2" \
	&& export MPI_FCFLAGS="-fopenmp -fallow-argument-mismatch -O2" \	
	&& export CPPFLAGS="-fallow-argument-mismatch -DOMNI_CPU_X86_64 -DOMNI_OS_LINUX -DGNU_SOURCE -D_REENTRANT" \
	&& ./configure --prefix=${PREFIX} --with-libxml2=/usr \
	&& make && make install && make clean && ldconfig



# Install  LLVM with Polly (branch stable)
WORKDIR /opt
RUN git clone --branch release/18.x https://github.com/llvm/llvm-project.git

# Configuration LLVM with Polly 
WORKDIR /opt/llvm-project/build
RUN cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="clang;lld;polly" \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DCMAKE_INSTALL_PREFIX=/usr/local/llvm \
    ../llvm \
    && ninja && ninja install


# Add LLVM to PATH
ENV PATH="/usr/local/llvm/bin:${PATH}"

# Install of Go official
RUN wget https://go.dev/dl/go1.24.1.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

# Add Go to PATH
ENV PATH="/usr/local/go/bin:${PATH}"

# Clone Gollvm
WORKDIR /opt

ENV PATH="/usr/local/bin:${PATH}"
# go1.18
ARG LLVMGO_VERSION=3452ec6bebaa1b432aabed1991475f4444c1775e
ARG GOFRONTEND_VERSION=1c5bfd57131b68b91d8400bb017f35d416f7aa7b
ARG LIBBACKTRACK_VERSION=fd9442f7b5413e7788dfcf356f6261afcedb56e8
ARG LIBFFI_VERSION=2e825e219fa06d308b9a9863d70320606d67490d

# llvm 15.0
ARG LLVM_VERSION=09629215c272f09e3ebde6cc7eac9625d28910ff
RUN cd llvm-project && git checkout ${LLVM_VERSION}

WORKDIR /opt
RUN cd llvm-project/llvm/tools && \
    git clone https://go.googlesource.com/gollvm && cd gollvm && git checkout ${LLVMGO_VERSION} && \
    git clone https://go.googlesource.com/gofrontend && cd gofrontend && git checkout ${GOFRONTEND_VERSION} && cd ../libgo && \
    git clone https://github.com/libffi/libffi.git && cd libffi && git checkout ${LIBFFI_VERSION} && cd .. && \
    git clone https://github.com/ianlancetaylor/libbacktrace.git && cd libbacktrace && git checkout ${LIBBACKTRACK_VERSION}
WORKDIR /opt/build.rel
RUN cmake -DCMAKE_INSTALL_PREFIX=/goroot -DCMAKE_BUILD_TYPE=Release -DLLVM_USE_LINKER=gold -G Ninja ../llvm-project/llvm
RUN ninja gollvm
RUN ninja install-gollvm

ENV LD_LIBRARY_PATH=/opt/build.rel/tools/gollvm/libgo
ARG LD_LIBRARY_PATH=/goroot/lib64
RUN export PATH=/tmp/gollvm-install/bin:$PATH
RUN /goroot/bin/go version


# Install of gopls (serveur de langage Go)
RUN go install golang.org/x/tools/gopls@latest

WORKDIR /opt
# script for Polly with llvm-goc
RUN echo '#!/bin/bash\n\
/goroot/bin/llvm-goc -O3 -mllvm -polly "$@"' > /usr/local/bin/llvm-goc-polly \
    && chmod +x /usr/local/bin/llvm-goc-polly

# Install of pocl

WORKDIR /opt
RUN git clone -b v6.0 https://github.com/pocl/pocl.git pocl_6.0
WORKDIR /opt/pocl_6.0
RUN mkdir -p /opt/pocl-6.0
RUN mkdir -p /opt/pocl_6.0/build
WORKDIR /opt/pocl_6.0/build
RUN cmake -DCMAKE_INSTALL_PREFIX=/opt/pocl-6.0 \ 
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-funroll-loops -march=native" \
        -DCMAKE_C_FLAGS="-funroll-loops -march=native" \ 
        -DWITH_LLVM_CONFIG=/usr/local/llvm/bin/llvm-config \
        -DPOCL_VULKAN_VALIDATE=ON \
        -DSTATIC_LLVM=ON \
        --trace-expand \
        --trace-source=CMakeLists.txt \
        ..
RUN make
RUN make install

ENV PATH="/opt/pocl-6.0/bin:${PATH}"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/pocl-6.0/lib"

# install check
RUN go version
RUN clang --version
RUN /opt/pocl-6.0/bin/poclcc -l	
RUN llvm-goc-polly --version
RUN vulkaninfo --summary

# Clean
RUN rm -rf /opt/llvm-project

# Commande par défaut
CMD ["bash"]
